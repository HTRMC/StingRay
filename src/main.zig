const std = @import("std");
const builtin = @import("builtin");
const c = @import("gpu/c.zig").c;

const enable_validation = builtin.mode == .Debug;
const validation_layers = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};
const device_extensions = [_][*:0]const u8{c.VK_KHR_SWAPCHAIN_EXTENSION_NAME};

const max_frames_in_flight: u32 = 2;

const CameraUbo = extern struct {
    lookfrom: [4]f32,
    lookat_vfov: [4]f32,
    vup_aspect: [4]f32,
    frame_size: [4]u32,
    counts: [4]u32, // sphere, quad, material, accum_index
    extra: [4]u32, // light_count, _, _, _
};

const Camera = struct {
    lookfrom: [3]f32 = .{ 278.0, 278.0, -800.0 },
    lookat: [3]f32 = .{ 278.0, 278.0, 0.0 },
    vup: [3]f32 = .{ 0.0, 1.0, 0.0 },
    vfov_deg: f32 = 40.0,
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    frame_idx: u32 = 0,
};

const MatType = enum(u32) { lambertian = 0, metal = 1, dielectric = 2, emissive = 3 };

const MaterialGpu = extern struct {
    albedo: [4]f32, // xyz=color, w=fuzz_or_ior
    type_pad: [4]u32,
};

const SphereGpu = extern struct {
    center_radius: [4]f32,
    mat_idx: [4]u32,
};

const QuadGpu = extern struct {
    q: [4]f32,
    u: [4]f32,
    v: [4]f32,
    n_d: [4]f32, // xyz normal unit, w D
    w_vec: [4]f32, // xyz w (n / dot(n, cross(u,v))), w pad
    mat_pad: [4]u32,
};

fn vec4(x: f32, y: f32, z: f32, w: f32) [4]f32 {
    return .{ x, y, z, w };
}

fn cross3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn normalize3(a: [3]f32) [3]f32 {
    const l = @sqrt(dot3(a, a));
    return .{ a[0] / l, a[1] / l, a[2] / l };
}

const BvhNodeGpu = extern struct {
    aabb_min: [3]f32,
    left_or_first: u32,
    aabb_max: [3]f32,
    right_or_count: u32, // high bit set = leaf; low 31 = prim_count for leaf, right_idx for inner
};

const PrimType = enum(u32) { sphere = 0, quad = 1 };

const Aabb = struct {
    min: [3]f32,
    max: [3]f32,

    fn empty() Aabb {
        return .{ .min = .{ std.math.inf(f32), std.math.inf(f32), std.math.inf(f32) }, .max = .{ -std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32) } };
    }

    fn unionAabb(a: Aabb, b: Aabb) Aabb {
        return .{
            .min = .{ @min(a.min[0], b.min[0]), @min(a.min[1], b.min[1]), @min(a.min[2], b.min[2]) },
            .max = .{ @max(a.max[0], b.max[0]), @max(a.max[1], b.max[1]), @max(a.max[2], b.max[2]) },
        };
    }

    fn pad(a: Aabb) Aabb {
        const eps: f32 = 1e-4;
        return .{
            .min = .{ a.min[0] - eps, a.min[1] - eps, a.min[2] - eps },
            .max = .{ a.max[0] + eps, a.max[1] + eps, a.max[2] + eps },
        };
    }

    fn centroid(a: Aabb) [3]f32 {
        return .{ 0.5 * (a.min[0] + a.max[0]), 0.5 * (a.min[1] + a.max[1]), 0.5 * (a.min[2] + a.max[2]) };
    }

    fn longestAxis(a: Aabb) u32 {
        const d = [3]f32{ a.max[0] - a.min[0], a.max[1] - a.min[1], a.max[2] - a.min[2] };
        if (d[0] >= d[1] and d[0] >= d[2]) return 0;
        if (d[1] >= d[2]) return 1;
        return 2;
    }
};

fn sphereAabb(s: SphereGpu) Aabb {
    const ctr = s.center_radius;
    const r = ctr[3];
    return (Aabb{
        .min = .{ ctr[0] - r, ctr[1] - r, ctr[2] - r },
        .max = .{ ctr[0] + r, ctr[1] + r, ctr[2] + r },
    }).pad();
}

fn quadAabb(q: QuadGpu) Aabb {
    const a = [3]f32{ q.q[0], q.q[1], q.q[2] };
    const b = [3]f32{ a[0] + q.u[0], a[1] + q.u[1], a[2] + q.u[2] };
    const cc = [3]f32{ a[0] + q.v[0], a[1] + q.v[1], a[2] + q.v[2] };
    const d = [3]f32{ a[0] + q.u[0] + q.v[0], a[1] + q.u[1] + q.v[1], a[2] + q.u[2] + q.v[2] };
    return (Aabb{
        .min = .{ @min(@min(a[0], b[0]), @min(cc[0], d[0])), @min(@min(a[1], b[1]), @min(cc[1], d[1])), @min(@min(a[2], b[2]), @min(cc[2], d[2])) },
        .max = .{ @max(@max(a[0], b[0]), @max(cc[0], d[0])), @max(@max(a[1], b[1]), @max(cc[1], d[1])), @max(@max(a[2], b[2]), @max(cc[2], d[2])) },
    }).pad();
}

fn makeQuad(q: [3]f32, u: [3]f32, v: [3]f32, mat: u32) QuadGpu {
    const n_raw = cross3(u, v);
    const n = normalize3(n_raw);
    const D = dot3(n, q);
    const denom = dot3(n_raw, n_raw);
    const w = [3]f32{ n_raw[0] / denom, n_raw[1] / denom, n_raw[2] / denom };
    return .{
        .q = .{ q[0], q[1], q[2], 0 },
        .u = .{ u[0], u[1], u[2], 0 },
        .v = .{ v[0], v[1], v[2], 0 },
        .n_d = .{ n[0], n[1], n[2], D },
        .w_vec = .{ w[0], w[1], w[2], 0 },
        .mat_pad = .{ mat, 0, 0, 0 },
    };
}

const QueueFamilies = struct {
    graphics: u32,
    present: u32,
};

const SwapchainSupport = struct {
    capabilities: c.VkSurfaceCapabilitiesKHR,
    formats: []c.VkSurfaceFormatKHR,
    present_modes: []c.VkPresentModeKHR,

    fn deinit(self: *SwapchainSupport, alloc: std.mem.Allocator) void {
        alloc.free(self.formats);
        alloc.free(self.present_modes);
    }
};

const App = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    window: *c.GLFWwindow,

    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,

    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    queue_families: QueueFamilies,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,

    swapchain: c.VkSwapchainKHR,
    swapchain_images: []c.VkImage,
    swapchain_image_views: []c.VkImageView,
    swapchain_format: c.VkFormat,
    swapchain_extent: c.VkExtent2D,

    accum_image: c.VkImage,
    accum_image_memory: c.VkDeviceMemory,
    accum_image_view: c.VkImageView,
    accum_image_layout: c.VkImageLayout,

    display_image: c.VkImage,
    display_image_memory: c.VkDeviceMemory,
    display_image_view: c.VkImageView,
    display_image_layout: c.VkImageLayout,

    accum_index: u32,
    prev_camera: Camera,

    last_time: f64,
    prev_mouse_x: f64,
    prev_mouse_y: f64,
    looking: bool,

    descriptor_set_layout: c.VkDescriptorSetLayout,
    descriptor_pool: c.VkDescriptorPool,
    descriptor_set: c.VkDescriptorSet,
    pipeline_layout: c.VkPipelineLayout,
    compute_pipeline: c.VkPipeline,
    shader_module: c.VkShaderModule,

    ubo_buffer: c.VkBuffer,
    ubo_memory: c.VkDeviceMemory,
    ubo_mapped: *CameraUbo,

    sphere_buffer: c.VkBuffer,
    sphere_memory: c.VkDeviceMemory,
    sphere_count: u32,

    quad_buffer: c.VkBuffer,
    quad_memory: c.VkDeviceMemory,
    quad_count: u32,

    material_buffer: c.VkBuffer,
    material_memory: c.VkDeviceMemory,
    material_count: u32,

    light_buffer: c.VkBuffer,
    light_memory: c.VkDeviceMemory,
    light_count: u32,

    bvh_buffer: c.VkBuffer,
    bvh_memory: c.VkDeviceMemory,
    bvh_node_count: u32,

    primref_buffer: c.VkBuffer,
    primref_memory: c.VkDeviceMemory,
    primref_count: u32,

    camera: Camera,

    command_pool: c.VkCommandPool,
    command_buffers: [max_frames_in_flight]c.VkCommandBuffer,

    image_available_sems: [max_frames_in_flight]c.VkSemaphore,
    render_finished_sems: []c.VkSemaphore, // one per swapchain image
    in_flight_fences: [max_frames_in_flight]c.VkFence,

    current_frame: u32 = 0,
    framebuffer_resized: bool = false,
};

var g_app: ?*App = null;

fn vkCheck(result: c.VkResult) !void {
    if (result != c.VK_SUCCESS) {
        std.debug.print("Vulkan error: {}\n", .{result});
        return error.VulkanError;
    }
}

pub fn main(init: std.process.Init) !void {
    const alloc = std.heap.page_allocator;
    const io = init.io;

    if (c.glfwInit() == 0) return error.GlfwInitFailed;
    defer c.glfwTerminate();
    if (c.glfwVulkanSupported() == 0) return error.VulkanUnsupported;

    c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
    c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);
    const window = c.glfwCreateWindow(1280, 720, "StingRay GPU", null, null) orelse return error.WindowCreateFailed;
    defer c.glfwDestroyWindow(window);

    var app: App = undefined;
    app.alloc = alloc;
    app.io = io;
    app.window = window;
    app.current_frame = 0;
    app.framebuffer_resized = false;
    app.camera = .{};
    app.prev_camera = app.camera;
    app.accum_index = 0;
    app.last_time = c.glfwGetTime();
    app.prev_mouse_x = 0;
    app.prev_mouse_y = 0;
    app.looking = false;
    g_app = &app;
    _ = c.glfwSetFramebufferSizeCallback(window, framebufferResizeCallback);

    try createInstance(&app);
    defer c.vkDestroyInstance(app.instance, null);

    try setupDebugMessenger(&app);
    defer if (enable_validation) destroyDebugMessenger(&app);

    try createSurface(&app);
    defer c.vkDestroySurfaceKHR(app.instance, app.surface, null);

    try pickPhysicalDevice(&app);
    try createLogicalDevice(&app);
    defer c.vkDestroyDevice(app.device, null);

    try createSwapchain(&app);
    defer destroySwapchain(&app);

    try createDescriptorSetLayout(&app);
    defer c.vkDestroyDescriptorSetLayout(app.device, app.descriptor_set_layout, null);

    try createComputePipeline(&app);
    defer {
        c.vkDestroyPipeline(app.device, app.compute_pipeline, null);
        c.vkDestroyPipelineLayout(app.device, app.pipeline_layout, null);
        c.vkDestroyShaderModule(app.device, app.shader_module, null);
    }

    try createDescriptorPool(&app);
    defer c.vkDestroyDescriptorPool(app.device, app.descriptor_pool, null);

    try createUniformBuffer(&app);
    defer destroyUniformBuffer(&app);

    try buildSceneCornellBox(&app);
    defer destroySceneBuffers(&app);

    try createStorageImage(&app);
    defer destroyStorageImage(&app);

    try createDescriptorSet(&app);
    updateDescriptorSet(&app);

    try createCommandPool(&app);
    defer c.vkDestroyCommandPool(app.device, app.command_pool, null);

    try createCommandBuffers(&app);
    try createSyncObjects(&app);
    defer destroySyncObjects(&app);

    std.debug.print("Vulkan initialised. {d} swapchain images at {d}x{d}.\n", .{
        app.swapchain_images.len, app.swapchain_extent.width, app.swapchain_extent.height,
    });

    while (c.glfwWindowShouldClose(window) == 0) {
        c.glfwPollEvents();
        if (c.glfwGetKey(window, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS) {
            c.glfwSetWindowShouldClose(window, 1);
        }
        updateCamera(&app);
        try drawFrame(&app);
    }

    _ = c.vkDeviceWaitIdle(app.device);
}

fn framebufferResizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    _ = width;
    _ = height;
    if (g_app) |a| a.framebuffer_resized = true;
}

// -----------------------------------------------------------------------------
// Instance + validation
// -----------------------------------------------------------------------------

fn createInstance(app: *App) !void {
    if (enable_validation and !try checkValidationSupport(app.alloc)) {
        std.debug.print("validation layers not available, continuing without them\n", .{});
    }

    var app_info: c.VkApplicationInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "StingRay",
        .applicationVersion = c.VK_MAKE_API_VERSION(0, 0, 1, 0),
        .pEngineName = "StingRay",
        .engineVersion = c.VK_MAKE_API_VERSION(0, 0, 1, 0),
        .apiVersion = c.VK_API_VERSION_1_2,
    };

    var ext_count: u32 = 0;
    const glfw_exts = c.glfwGetRequiredInstanceExtensions(&ext_count);
    var exts = try std.ArrayList([*:0]const u8).initCapacity(app.alloc, ext_count + 1);
    defer exts.deinit(app.alloc);
    var i: u32 = 0;
    while (i < ext_count) : (i += 1) try exts.append(app.alloc, @ptrCast(glfw_exts[i]));
    if (enable_validation) try exts.append(app.alloc, c.VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    var create_info: c.VkInstanceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app_info,
        .enabledExtensionCount = @intCast(exts.items.len),
        .ppEnabledExtensionNames = exts.items.ptr,
    };

    var debug_ci: c.VkDebugUtilsMessengerCreateInfoEXT = makeDebugCreateInfo();
    if (enable_validation) {
        create_info.enabledLayerCount = validation_layers.len;
        create_info.ppEnabledLayerNames = &validation_layers;
        create_info.pNext = &debug_ci;
    }

    try vkCheck(c.vkCreateInstance(&create_info, null, &app.instance));
}

fn checkValidationSupport(alloc: std.mem.Allocator) !bool {
    var count: u32 = 0;
    _ = c.vkEnumerateInstanceLayerProperties(&count, null);
    const props = try alloc.alloc(c.VkLayerProperties, count);
    defer alloc.free(props);
    _ = c.vkEnumerateInstanceLayerProperties(&count, props.ptr);

    for (validation_layers) |needed| {
        var found = false;
        for (props) |p| {
            const name_slice = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&p.layerName)), 0);
            if (std.mem.eql(u8, name_slice, std.mem.sliceTo(needed, 0))) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn debugCallback(
    severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    msg_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    data: [*c]const c.VkDebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = msg_type;
    if (severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        std.debug.print("[VK] {s}\n", .{data.*.pMessage});
    }
    return c.VK_FALSE;
}

fn makeDebugCreateInfo() c.VkDebugUtilsMessengerCreateInfoEXT {
    return .{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
        .messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT,
        .messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
            c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
        .pfnUserCallback = debugCallback,
    };
}

fn setupDebugMessenger(app: *App) !void {
    if (!enable_validation) return;
    const ci = makeDebugCreateInfo();
    const fn_ptr = c.vkGetInstanceProcAddr(app.instance, "vkCreateDebugUtilsMessengerEXT");
    if (fn_ptr == null) return error.DebugMessengerMissing;
    const create: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(fn_ptr);
    try vkCheck(create.?(app.instance, &ci, null, &app.debug_messenger));
}

fn destroyDebugMessenger(app: *App) void {
    const fn_ptr = c.vkGetInstanceProcAddr(app.instance, "vkDestroyDebugUtilsMessengerEXT");
    if (fn_ptr == null) return;
    const destroy: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(fn_ptr);
    destroy.?(app.instance, app.debug_messenger, null);
}

// -----------------------------------------------------------------------------
// Surface
// -----------------------------------------------------------------------------

fn createSurface(app: *App) !void {
    try vkCheck(c.glfwCreateWindowSurface(app.instance, app.window, null, &app.surface));
}

// -----------------------------------------------------------------------------
// Physical device
// -----------------------------------------------------------------------------

fn pickPhysicalDevice(app: *App) !void {
    var count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(app.instance, &count, null);
    if (count == 0) return error.NoVulkanDevice;
    const devices = try app.alloc.alloc(c.VkPhysicalDevice, count);
    defer app.alloc.free(devices);
    _ = c.vkEnumeratePhysicalDevices(app.instance, &count, devices.ptr);

    var best: ?c.VkPhysicalDevice = null;
    var best_score: i32 = -1;
    for (devices) |dev| {
        const score = try scoreDevice(app, dev);
        if (score > best_score) {
            best_score = score;
            best = dev;
        }
    }
    if (best_score < 0) return error.NoSuitableDevice;
    app.physical_device = best.?;

    var props: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(app.physical_device, &props);
    std.debug.print("Picked GPU: {s}\n", .{std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&props.deviceName)), 0)});

    app.queue_families = (try findQueueFamilies(app, app.physical_device)).?;
}

fn scoreDevice(app: *App, dev: c.VkPhysicalDevice) !i32 {
    if ((try findQueueFamilies(app, dev)) == null) return -1;
    if (!try checkDeviceExtensions(app, dev)) return -1;

    var support = try querySwapchainSupport(app, dev);
    defer support.deinit(app.alloc);
    if (support.formats.len == 0 or support.present_modes.len == 0) return -1;

    var props: c.VkPhysicalDeviceProperties = undefined;
    c.vkGetPhysicalDeviceProperties(dev, &props);
    var score: i32 = 0;
    if (props.deviceType == c.VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) score += 1000;
    score += @intCast(props.limits.maxImageDimension2D);
    return score;
}

fn findQueueFamilies(app: *App, dev: c.VkPhysicalDevice) !?QueueFamilies {
    var count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &count, null);
    const fams = try app.alloc.alloc(c.VkQueueFamilyProperties, count);
    defer app.alloc.free(fams);
    c.vkGetPhysicalDeviceQueueFamilyProperties(dev, &count, fams.ptr);

    var graphics: ?u32 = null;
    var present: ?u32 = null;
    for (fams, 0..) |f, idx| {
        const i: u32 = @intCast(idx);
        const has_gfx_compute = (f.queueFlags & c.VK_QUEUE_GRAPHICS_BIT) != 0 and
            (f.queueFlags & c.VK_QUEUE_COMPUTE_BIT) != 0;
        if (graphics == null and has_gfx_compute) graphics = i;
        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(dev, i, app.surface, &present_support);
        if (present == null and present_support == c.VK_TRUE) present = i;
        if (graphics != null and present != null) break;
    }
    if (graphics == null or present == null) return null;
    return .{ .graphics = graphics.?, .present = present.? };
}

fn checkDeviceExtensions(app: *App, dev: c.VkPhysicalDevice) !bool {
    var count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(dev, null, &count, null);
    const props = try app.alloc.alloc(c.VkExtensionProperties, count);
    defer app.alloc.free(props);
    _ = c.vkEnumerateDeviceExtensionProperties(dev, null, &count, props.ptr);

    for (device_extensions) |needed| {
        var found = false;
        for (props) |p| {
            const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&p.extensionName)), 0);
            if (std.mem.eql(u8, name, std.mem.sliceTo(needed, 0))) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn querySwapchainSupport(app: *App, dev: c.VkPhysicalDevice) !SwapchainSupport {
    var caps: c.VkSurfaceCapabilitiesKHR = undefined;
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(dev, app.surface, &caps);

    var fmt_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(dev, app.surface, &fmt_count, null);
    const formats = try app.alloc.alloc(c.VkSurfaceFormatKHR, fmt_count);
    if (fmt_count > 0) _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(dev, app.surface, &fmt_count, formats.ptr);

    var pm_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(dev, app.surface, &pm_count, null);
    const pms = try app.alloc.alloc(c.VkPresentModeKHR, pm_count);
    if (pm_count > 0) _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(dev, app.surface, &pm_count, pms.ptr);

    return .{ .capabilities = caps, .formats = formats, .present_modes = pms };
}

// -----------------------------------------------------------------------------
// Logical device
// -----------------------------------------------------------------------------

fn createLogicalDevice(app: *App) !void {
    const priority: f32 = 1.0;
    var queue_infos: [2]c.VkDeviceQueueCreateInfo = undefined;
    var queue_info_count: u32 = 0;
    queue_infos[queue_info_count] = .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = app.queue_families.graphics,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    queue_info_count += 1;
    if (app.queue_families.present != app.queue_families.graphics) {
        queue_infos[queue_info_count] = .{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = app.queue_families.present,
            .queueCount = 1,
            .pQueuePriorities = &priority,
        };
        queue_info_count += 1;
    }

    var features: c.VkPhysicalDeviceFeatures = .{};

    var create_info: c.VkDeviceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = queue_info_count,
        .pQueueCreateInfos = &queue_infos,
        .pEnabledFeatures = &features,
        .enabledExtensionCount = device_extensions.len,
        .ppEnabledExtensionNames = &device_extensions,
    };

    try vkCheck(c.vkCreateDevice(app.physical_device, &create_info, null, &app.device));

    c.vkGetDeviceQueue(app.device, app.queue_families.graphics, 0, &app.graphics_queue);
    c.vkGetDeviceQueue(app.device, app.queue_families.present, 0, &app.present_queue);
}

// -----------------------------------------------------------------------------
// Swapchain
// -----------------------------------------------------------------------------

fn createSwapchain(app: *App) !void {
    var support = try querySwapchainSupport(app, app.physical_device);
    defer support.deinit(app.alloc);

    const fmt = pickSurfaceFormat(support.formats);
    const present_mode = pickPresentMode(support.present_modes);
    const extent = pickExtent(app.window, support.capabilities);

    var image_count: u32 = support.capabilities.minImageCount + 1;
    if (support.capabilities.maxImageCount > 0 and image_count > support.capabilities.maxImageCount) {
        image_count = support.capabilities.maxImageCount;
    }

    var ci: c.VkSwapchainCreateInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = app.surface,
        .minImageCount = image_count,
        .imageFormat = fmt.format,
        .imageColorSpace = fmt.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT,
        .preTransform = support.capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    const qf_indices = [_]u32{ app.queue_families.graphics, app.queue_families.present };
    if (app.queue_families.graphics != app.queue_families.present) {
        ci.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        ci.queueFamilyIndexCount = 2;
        ci.pQueueFamilyIndices = &qf_indices;
    } else {
        ci.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    }

    try vkCheck(c.vkCreateSwapchainKHR(app.device, &ci, null, &app.swapchain));
    app.swapchain_format = fmt.format;
    app.swapchain_extent = extent;

    var sc_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(app.device, app.swapchain, &sc_count, null);
    app.swapchain_images = try app.alloc.alloc(c.VkImage, sc_count);
    _ = c.vkGetSwapchainImagesKHR(app.device, app.swapchain, &sc_count, app.swapchain_images.ptr);

    app.swapchain_image_views = try app.alloc.alloc(c.VkImageView, sc_count);
    for (app.swapchain_images, 0..) |img, i| {
        const view_ci: c.VkImageViewCreateInfo = .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = img,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = fmt.format,
            .components = .{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = .{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };
        try vkCheck(c.vkCreateImageView(app.device, &view_ci, null, &app.swapchain_image_views[i]));
    }

    // render-finished sem per swapchain image (avoids reuse-in-flight stalls)
    app.render_finished_sems = try app.alloc.alloc(c.VkSemaphore, sc_count);
    const sem_ci: c.VkSemaphoreCreateInfo = .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    for (app.render_finished_sems) |*s| try vkCheck(c.vkCreateSemaphore(app.device, &sem_ci, null, s));
}

fn destroySwapchain(app: *App) void {
    for (app.render_finished_sems) |s| c.vkDestroySemaphore(app.device, s, null);
    app.alloc.free(app.render_finished_sems);
    for (app.swapchain_image_views) |v| c.vkDestroyImageView(app.device, v, null);
    app.alloc.free(app.swapchain_image_views);
    app.alloc.free(app.swapchain_images);
    c.vkDestroySwapchainKHR(app.device, app.swapchain, null);
}

fn pickSurfaceFormat(formats: []c.VkSurfaceFormatKHR) c.VkSurfaceFormatKHR {
    for (formats) |f| {
        if (f.format == c.VK_FORMAT_B8G8R8A8_UNORM and f.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) return f;
    }
    return formats[0];
}

fn pickPresentMode(modes: []c.VkPresentModeKHR) c.VkPresentModeKHR {
    for (modes) |m| {
        if (m == c.VK_PRESENT_MODE_MAILBOX_KHR) return m;
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn pickExtent(window: *c.GLFWwindow, caps: c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) return caps.currentExtent;
    var w: c_int = 0;
    var h: c_int = 0;
    c.glfwGetFramebufferSize(window, &w, &h);
    return .{
        .width = std.math.clamp(@as(u32, @intCast(w)), caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(@as(u32, @intCast(h)), caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}

fn recreateSwapchain(app: *App) !void {
    var w: c_int = 0;
    var h: c_int = 0;
    c.glfwGetFramebufferSize(app.window, &w, &h);
    while (w == 0 or h == 0) {
        c.glfwGetFramebufferSize(app.window, &w, &h);
        c.glfwWaitEvents();
    }
    _ = c.vkDeviceWaitIdle(app.device);
    destroySwapchain(app);
    destroyStorageImage(app);
    try createSwapchain(app);
    try createStorageImage(app);
    updateDescriptorSet(app);
}

// -----------------------------------------------------------------------------
// Command pool + buffers + sync
// -----------------------------------------------------------------------------

fn createCommandPool(app: *App) !void {
    const ci: c.VkCommandPoolCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = app.queue_families.graphics,
    };
    try vkCheck(c.vkCreateCommandPool(app.device, &ci, null, &app.command_pool));
}

fn createCommandBuffers(app: *App) !void {
    const ai: c.VkCommandBufferAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = app.command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = max_frames_in_flight,
    };
    try vkCheck(c.vkAllocateCommandBuffers(app.device, &ai, &app.command_buffers));
}

fn createSyncObjects(app: *App) !void {
    const sem_ci: c.VkSemaphoreCreateInfo = .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    const fence_ci: c.VkFenceCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
    };
    var i: u32 = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        try vkCheck(c.vkCreateSemaphore(app.device, &sem_ci, null, &app.image_available_sems[i]));
        try vkCheck(c.vkCreateFence(app.device, &fence_ci, null, &app.in_flight_fences[i]));
    }
}

fn destroySyncObjects(app: *App) void {
    var i: u32 = 0;
    while (i < max_frames_in_flight) : (i += 1) {
        c.vkDestroySemaphore(app.device, app.image_available_sems[i], null);
        c.vkDestroyFence(app.device, app.in_flight_fences[i], null);
    }
}

// -----------------------------------------------------------------------------
// Render
// -----------------------------------------------------------------------------

fn drawFrame(app: *App) !void {
    _ = c.vkWaitForFences(app.device, 1, &app.in_flight_fences[app.current_frame], c.VK_TRUE, std.math.maxInt(u64));

    var image_index: u32 = 0;
    const acquire = c.vkAcquireNextImageKHR(
        app.device,
        app.swapchain,
        std.math.maxInt(u64),
        app.image_available_sems[app.current_frame],
        null,
        &image_index,
    );
    if (acquire == c.VK_ERROR_OUT_OF_DATE_KHR) {
        try recreateSwapchain(app);
        return;
    } else if (acquire != c.VK_SUCCESS and acquire != c.VK_SUBOPTIMAL_KHR) {
        return error.AcquireFailed;
    }

    _ = c.vkResetFences(app.device, 1, &app.in_flight_fences[app.current_frame]);

    updateUbo(app);

    const cb = app.command_buffers[app.current_frame];
    _ = c.vkResetCommandBuffer(cb, 0);
    try recordCommandBuffer(app, cb, image_index);

    const wait_stages = [_]c.VkPipelineStageFlags{c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT};
    const submit: c.VkSubmitInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &app.image_available_sems[app.current_frame],
        .pWaitDstStageMask = &wait_stages,
        .commandBufferCount = 1,
        .pCommandBuffers = &app.command_buffers[app.current_frame],
        .signalSemaphoreCount = 1,
        .pSignalSemaphores = &app.render_finished_sems[image_index],
    };
    try vkCheck(c.vkQueueSubmit(app.graphics_queue, 1, &submit, app.in_flight_fences[app.current_frame]));

    const present: c.VkPresentInfoKHR = .{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .waitSemaphoreCount = 1,
        .pWaitSemaphores = &app.render_finished_sems[image_index],
        .swapchainCount = 1,
        .pSwapchains = &app.swapchain,
        .pImageIndices = &image_index,
    };
    const present_res = c.vkQueuePresentKHR(app.present_queue, &present);
    if (present_res == c.VK_ERROR_OUT_OF_DATE_KHR or present_res == c.VK_SUBOPTIMAL_KHR or app.framebuffer_resized) {
        app.framebuffer_resized = false;
        try recreateSwapchain(app);
    } else if (present_res != c.VK_SUCCESS) {
        return error.PresentFailed;
    }

    app.current_frame = (app.current_frame + 1) % max_frames_in_flight;
}

fn recordCommandBuffer(app: *App, cb: c.VkCommandBuffer, image_index: u32) !void {
    const begin: c.VkCommandBufferBeginInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
    };
    try vkCheck(c.vkBeginCommandBuffer(cb, &begin));

    // accum: ensure GENERAL (preserve contents)
    transitionImage(cb, app.accum_image, app.accum_image_layout, c.VK_IMAGE_LAYOUT_GENERAL);
    app.accum_image_layout = c.VK_IMAGE_LAYOUT_GENERAL;

    // display: GENERAL for compute write
    transitionImage(cb, app.display_image, app.display_image_layout, c.VK_IMAGE_LAYOUT_GENERAL);
    app.display_image_layout = c.VK_IMAGE_LAYOUT_GENERAL;

    c.vkCmdBindPipeline(cb, c.VK_PIPELINE_BIND_POINT_COMPUTE, app.compute_pipeline);
    c.vkCmdBindDescriptorSets(cb, c.VK_PIPELINE_BIND_POINT_COMPUTE, app.pipeline_layout, 0, 1, &app.descriptor_set, 0, null);
    const gx: u32 = (app.swapchain_extent.width + 7) / 8;
    const gy: u32 = (app.swapchain_extent.height + 7) / 8;
    c.vkCmdDispatch(cb, gx, gy, 1);

    // display GENERAL -> TRANSFER_SRC, swapchain UNDEFINED -> TRANSFER_DST
    transitionImage(cb, app.display_image, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    app.display_image_layout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    transitionImage(cb, app.swapchain_images[image_index], c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    const blit: c.VkImageBlit = .{
        .srcSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .srcOffsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = @intCast(app.swapchain_extent.width), .y = @intCast(app.swapchain_extent.height), .z = 1 },
        },
        .dstSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .dstOffsets = .{
            .{ .x = 0, .y = 0, .z = 0 },
            .{ .x = @intCast(app.swapchain_extent.width), .y = @intCast(app.swapchain_extent.height), .z = 1 },
        },
    };
    c.vkCmdBlitImage(
        cb,
        app.display_image,
        c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
        app.swapchain_images[image_index],
        c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
        1,
        &blit,
        c.VK_FILTER_LINEAR,
    );

    transitionImage(cb, app.swapchain_images[image_index], c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);

    try vkCheck(c.vkEndCommandBuffer(cb));
}

fn transitionImage(cb: c.VkCommandBuffer, img: c.VkImage, old: c.VkImageLayout, new: c.VkImageLayout) void {
    var barrier: c.VkImageMemoryBarrier = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .oldLayout = old,
        .newLayout = new,
        .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
        .image = img,
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };

    var src_stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    var dst_stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;

    if (old == c.VK_IMAGE_LAYOUT_UNDEFINED and new == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old == c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL and new == c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR) {
        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = 0;
        src_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
    } else if (old == c.VK_IMAGE_LAYOUT_UNDEFINED and new == c.VK_IMAGE_LAYOUT_GENERAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT;
        src_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    } else if (old == c.VK_IMAGE_LAYOUT_GENERAL and new == c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL) {
        barrier.srcAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
        src_stage = c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else if (old == c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL and new == c.VK_IMAGE_LAYOUT_GENERAL) {
        barrier.srcAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT;
        src_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    } else if (old == c.VK_IMAGE_LAYOUT_GENERAL and new == c.VK_IMAGE_LAYOUT_GENERAL) {
        barrier.srcAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT;
        barrier.dstAccessMask = c.VK_ACCESS_SHADER_WRITE_BIT;
        src_stage = c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
    }

    c.vkCmdPipelineBarrier(cb, src_stage, dst_stage, 0, 0, null, 0, null, 1, &barrier);
}

// -----------------------------------------------------------------------------
// Accum + display images
// -----------------------------------------------------------------------------

const accum_format: c.VkFormat = c.VK_FORMAT_R32G32B32A32_SFLOAT;
const display_format: c.VkFormat = c.VK_FORMAT_R8G8B8A8_UNORM;

fn createImage2D(app: *App, fmt: c.VkFormat, usage: c.VkImageUsageFlags, image: *c.VkImage, memory: *c.VkDeviceMemory, view: *c.VkImageView) !void {
    const image_ci: c.VkImageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .imageType = c.VK_IMAGE_TYPE_2D,
        .format = fmt,
        .extent = .{ .width = app.swapchain_extent.width, .height = app.swapchain_extent.height, .depth = 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .tiling = c.VK_IMAGE_TILING_OPTIMAL,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
    };
    try vkCheck(c.vkCreateImage(app.device, &image_ci, null, image));

    var mem_req: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(app.device, image.*, &mem_req);
    const mem_type = try findMemoryType(app, mem_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    const ai: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    };
    try vkCheck(c.vkAllocateMemory(app.device, &ai, null, memory));
    try vkCheck(c.vkBindImageMemory(app.device, image.*, memory.*, 0));

    const view_ci: c.VkImageViewCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        .image = image.*,
        .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
        .format = fmt,
        .components = .{
            .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
        },
        .subresourceRange = .{
            .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
            .baseMipLevel = 0,
            .levelCount = 1,
            .baseArrayLayer = 0,
            .layerCount = 1,
        },
    };
    try vkCheck(c.vkCreateImageView(app.device, &view_ci, null, view));
}

fn createStorageImage(app: *App) !void {
    try createImage2D(
        app,
        accum_format,
        c.VK_IMAGE_USAGE_STORAGE_BIT,
        &app.accum_image,
        &app.accum_image_memory,
        &app.accum_image_view,
    );
    try createImage2D(
        app,
        display_format,
        c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
        &app.display_image,
        &app.display_image_memory,
        &app.display_image_view,
    );
    app.display_image_layout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    app.accum_image_layout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    app.accum_index = 0;
}

fn destroyStorageImage(app: *App) void {
    c.vkDestroyImageView(app.device, app.accum_image_view, null);
    c.vkDestroyImage(app.device, app.accum_image, null);
    c.vkFreeMemory(app.device, app.accum_image_memory, null);
    c.vkDestroyImageView(app.device, app.display_image_view, null);
    c.vkDestroyImage(app.device, app.display_image, null);
    c.vkFreeMemory(app.device, app.display_image_memory, null);
}

fn findMemoryType(app: *App, type_bits: u32, props: c.VkMemoryPropertyFlags) !u32 {
    var mem_props: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(app.physical_device, &mem_props);
    var i: u32 = 0;
    while (i < mem_props.memoryTypeCount) : (i += 1) {
        const ok = (type_bits & (@as(u32, 1) << @intCast(i))) != 0;
        const has_props = (mem_props.memoryTypes[i].propertyFlags & props) == props;
        if (ok and has_props) return i;
    }
    return error.NoMemoryType;
}

// -----------------------------------------------------------------------------
// Descriptor set layout, pool, set
// -----------------------------------------------------------------------------

fn createDescriptorSetLayout(app: *App) !void {
    const bindings = [_]c.VkDescriptorSetLayoutBinding{
        .{ .binding = 0, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 2, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 3, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 4, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 5, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 6, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 7, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
        .{ .binding = 8, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1, .stageFlags = c.VK_SHADER_STAGE_COMPUTE_BIT },
    };
    const layout_ci: c.VkDescriptorSetLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = bindings.len,
        .pBindings = &bindings,
    };
    try vkCheck(c.vkCreateDescriptorSetLayout(app.device, &layout_ci, null, &app.descriptor_set_layout));
}

fn createDescriptorPool(app: *App) !void {
    const pool_sizes = [_]c.VkDescriptorPoolSize{
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 2 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .descriptorCount = 1 },
        .{ .type = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 6 },
    };
    const pool_ci: c.VkDescriptorPoolCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = 1,
        .poolSizeCount = pool_sizes.len,
        .pPoolSizes = &pool_sizes,
    };
    try vkCheck(c.vkCreateDescriptorPool(app.device, &pool_ci, null, &app.descriptor_pool));
}

fn createDescriptorSet(app: *App) !void {
    const ai: c.VkDescriptorSetAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = app.descriptor_pool,
        .descriptorSetCount = 1,
        .pSetLayouts = &app.descriptor_set_layout,
    };
    try vkCheck(c.vkAllocateDescriptorSets(app.device, &ai, &app.descriptor_set));
}

fn updateDescriptorSet(app: *App) void {
    const accum_info: c.VkDescriptorImageInfo = .{ .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL, .imageView = app.accum_image_view, .sampler = null };
    const display_info: c.VkDescriptorImageInfo = .{ .imageLayout = c.VK_IMAGE_LAYOUT_GENERAL, .imageView = app.display_image_view, .sampler = null };
    const ubo_info: c.VkDescriptorBufferInfo = .{ .buffer = app.ubo_buffer, .offset = 0, .range = @sizeOf(CameraUbo) };
    const sphere_info: c.VkDescriptorBufferInfo = .{ .buffer = app.sphere_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };
    const quad_info: c.VkDescriptorBufferInfo = .{ .buffer = app.quad_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };
    const mat_info: c.VkDescriptorBufferInfo = .{ .buffer = app.material_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };
    const light_info: c.VkDescriptorBufferInfo = .{ .buffer = app.light_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };
    const bvh_info: c.VkDescriptorBufferInfo = .{ .buffer = app.bvh_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };
    const primref_info: c.VkDescriptorBufferInfo = .{ .buffer = app.primref_buffer, .offset = 0, .range = c.VK_WHOLE_SIZE };

    const writes = [_]c.VkWriteDescriptorSet{
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 0, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &accum_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 1, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, .pBufferInfo = &ubo_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 2, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &sphere_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 3, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &quad_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 4, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &mat_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 5, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .pImageInfo = &display_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 6, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &light_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 7, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &bvh_info },
        .{ .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = app.descriptor_set, .dstBinding = 8, .descriptorCount = 1, .descriptorType = c.VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &primref_info },
    };
    c.vkUpdateDescriptorSets(app.device, writes.len, &writes, 0, null);
}

// -----------------------------------------------------------------------------
// Compute pipeline
// -----------------------------------------------------------------------------

fn createComputePipeline(app: *App) !void {
    const spv = try readShaderFile(app, "shaders/raytrace.comp.spv");
    defer app.alloc.free(spv);
    app.shader_module = try createShaderModule(app, spv);

    const stage_ci: c.VkPipelineShaderStageCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .stage = c.VK_SHADER_STAGE_COMPUTE_BIT,
        .module = app.shader_module,
        .pName = "main",
    };

    const pl_ci: c.VkPipelineLayoutCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .setLayoutCount = 1,
        .pSetLayouts = &app.descriptor_set_layout,
    };
    try vkCheck(c.vkCreatePipelineLayout(app.device, &pl_ci, null, &app.pipeline_layout));

    const pipe_ci: c.VkComputePipelineCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = stage_ci,
        .layout = app.pipeline_layout,
    };
    try vkCheck(c.vkCreateComputePipelines(app.device, null, 1, &pipe_ci, null, &app.compute_pipeline));
}

fn createShaderModule(app: *App, code: []const u8) !c.VkShaderModule {
    if (code.len % 4 != 0) return error.ShaderSize;
    const ci: c.VkShaderModuleCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = code.len,
        .pCode = @ptrCast(@alignCast(code.ptr)),
    };
    var module: c.VkShaderModule = undefined;
    try vkCheck(c.vkCreateShaderModule(app.device, &ci, null, &module));
    return module;
}

// -----------------------------------------------------------------------------
// BVH builder
// -----------------------------------------------------------------------------

const PrimDesc = struct {
    aabb: Aabb,
    ref: u32, // high bit set = quad, low 31 = idx
};

const max_leaf: usize = 4;

fn primSortLessThan(axis: u32, a: PrimDesc, b: PrimDesc) bool {
    return Aabb.centroid(a.aabb)[axis] < Aabb.centroid(b.aabb)[axis];
}

fn buildBvhRec(
    alloc: std.mem.Allocator,
    prims: []PrimDesc,
    nodes: *std.ArrayList(BvhNodeGpu),
    refs: *std.ArrayList(u32),
) !u32 {
    const this_idx: u32 = @intCast(nodes.items.len);
    try nodes.append(alloc, undefined);

    var bb = Aabb.empty();
    for (prims) |p| bb = Aabb.unionAabb(bb, p.aabb);

    if (prims.len <= max_leaf) {
        const first: u32 = @intCast(refs.items.len);
        for (prims) |p| try refs.append(alloc, p.ref);
        const cnt: u32 = @intCast(prims.len);
        nodes.items[this_idx] = .{
            .aabb_min = bb.min,
            .left_or_first = first,
            .aabb_max = bb.max,
            .right_or_count = 0x80000000 | cnt,
        };
        return this_idx;
    }

    var cb = Aabb.empty();
    for (prims) |p| {
        const ctr = Aabb.centroid(p.aabb);
        cb = Aabb.unionAabb(cb, .{ .min = ctr, .max = ctr });
    }
    const axis = Aabb.longestAxis(cb);

    std.mem.sort(PrimDesc, prims, axis, primSortLessThan);

    const mid = prims.len / 2;
    const left_idx = try buildBvhRec(alloc, prims[0..mid], nodes, refs);
    const right_idx = try buildBvhRec(alloc, prims[mid..], nodes, refs);

    nodes.items[this_idx] = .{
        .aabb_min = bb.min,
        .left_or_first = left_idx,
        .aabb_max = bb.max,
        .right_or_count = right_idx,
    };
    return this_idx;
}

fn buildBvh(
    app: *App,
    spheres: []const SphereGpu,
    quads: []const QuadGpu,
    out_nodes: *std.ArrayList(BvhNodeGpu),
    out_refs: *std.ArrayList(u32),
) !void {
    var prims: std.ArrayList(PrimDesc) = .empty;
    defer prims.deinit(app.alloc);
    for (spheres, 0..) |s, i| {
        try prims.append(app.alloc, .{ .aabb = sphereAabb(s), .ref = @as(u32, @intCast(i)) });
    }
    for (quads, 0..) |q, i| {
        try prims.append(app.alloc, .{ .aabb = quadAabb(q), .ref = (@as(u32, 1) << 31) | @as(u32, @intCast(i)) });
    }
    if (prims.items.len == 0) {
        try out_nodes.append(app.alloc, .{
            .aabb_min = .{ 0, 0, 0 },
            .left_or_first = 0,
            .aabb_max = .{ 0, 0, 0 },
            .right_or_count = 0x80000000,
        });
        return;
    }
    _ = try buildBvhRec(app.alloc, prims.items, out_nodes, out_refs);
}

// -----------------------------------------------------------------------------
// Scene buffers (host-visible coherent storage buffers)
// -----------------------------------------------------------------------------

fn createHostBuffer(app: *App, size: u64, usage: c.VkBufferUsageFlags, buffer: *c.VkBuffer, memory: *c.VkDeviceMemory) !void {
    const buf_ci: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = size,
        .usage = usage,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    try vkCheck(c.vkCreateBuffer(app.device, &buf_ci, null, buffer));

    var mem_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(app.device, buffer.*, &mem_req);

    const mem_type = try findMemoryType(
        app,
        mem_req.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    const ai: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    };
    try vkCheck(c.vkAllocateMemory(app.device, &ai, null, memory));
    try vkCheck(c.vkBindBufferMemory(app.device, buffer.*, memory.*, 0));
}

fn uploadHostBuffer(app: *App, memory: c.VkDeviceMemory, comptime T: type, data: []const T) !void {
    var raw: ?*anyopaque = null;
    const size: u64 = @sizeOf(T) * data.len;
    try vkCheck(c.vkMapMemory(app.device, memory, 0, size, 0, &raw));
    const dst_bytes: [*]u8 = @ptrCast(raw.?);
    const src_bytes: [*]const u8 = @ptrCast(data.ptr);
    @memcpy(dst_bytes[0..size], src_bytes[0..size]);
    c.vkUnmapMemory(app.device, memory);
}

fn buildSceneCornellBox(app: *App) !void {
    var mats: std.ArrayList(MaterialGpu) = .empty;
    defer mats.deinit(app.alloc);
    var spheres: std.ArrayList(SphereGpu) = .empty;
    defer spheres.deinit(app.alloc);
    var quads: std.ArrayList(QuadGpu) = .empty;
    defer quads.deinit(app.alloc);

    // Materials
    const m_red: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(0.65, 0.05, 0.05, 0), .type_pad = .{ @intFromEnum(MatType.lambertian), 0, 0, 0 } });
    const m_white: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(0.73, 0.73, 0.73, 0), .type_pad = .{ @intFromEnum(MatType.lambertian), 0, 0, 0 } });
    const m_green: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(0.12, 0.45, 0.15, 0), .type_pad = .{ @intFromEnum(MatType.lambertian), 0, 0, 0 } });
    const m_light: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(15.0, 15.0, 15.0, 0), .type_pad = .{ @intFromEnum(MatType.emissive), 0, 0, 0 } });

    // Cornell quads
    try quads.append(app.alloc, makeQuad(.{ 555, 0, 0 }, .{ 0, 555, 0 }, .{ 0, 0, 555 }, m_green));
    try quads.append(app.alloc, makeQuad(.{ 0, 0, 0 }, .{ 0, 555, 0 }, .{ 0, 0, 555 }, m_red));
    try quads.append(app.alloc, makeQuad(.{ 343, 554, 332 }, .{ -130, 0, 0 }, .{ 0, 0, -105 }, m_light));
    try quads.append(app.alloc, makeQuad(.{ 0, 0, 0 }, .{ 555, 0, 0 }, .{ 0, 0, 555 }, m_white));
    try quads.append(app.alloc, makeQuad(.{ 555, 555, 555 }, .{ -555, 0, 0 }, .{ 0, 0, -555 }, m_white));
    try quads.append(app.alloc, makeQuad(.{ 0, 0, 555 }, .{ 555, 0, 0 }, .{ 0, 555, 0 }, m_white));

    // Glass sphere
    const m_glass: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(1.0, 1.0, 1.0, 1.5), .type_pad = .{ @intFromEnum(MatType.dielectric), 0, 0, 0 } });
    try spheres.append(app.alloc, .{ .center_radius = vec4(190, 90, 190, 90), .mat_idx = .{ m_glass, 0, 0, 0 } });

    // Aluminum metal sphere
    const m_metal: u32 = @intCast(mats.items.len);
    try mats.append(app.alloc, .{ .albedo = vec4(0.8, 0.85, 0.88, 0.0), .type_pad = .{ @intFromEnum(MatType.metal), 0, 0, 0 } });
    try spheres.append(app.alloc, .{ .center_radius = vec4(380, 90, 380, 90), .mat_idx = .{ m_metal, 0, 0, 0 } });

    // Lights: copy quads whose material is emissive
    var lights: std.ArrayList(QuadGpu) = .empty;
    defer lights.deinit(app.alloc);
    for (quads.items) |q| {
        const mat = mats.items[q.mat_pad[0]];
        if (mat.type_pad[0] == @intFromEnum(MatType.emissive)) try lights.append(app.alloc, q);
    }

    app.material_count = @intCast(mats.items.len);
    app.sphere_count = @intCast(spheres.items.len);
    app.quad_count = @intCast(quads.items.len);
    app.light_count = @intCast(lights.items.len);

    // Materials buffer
    const mat_size: u64 = @max(@sizeOf(MaterialGpu), @sizeOf(MaterialGpu) * mats.items.len);
    try createHostBuffer(app, mat_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.material_buffer, &app.material_memory);
    try uploadHostBuffer(app, app.material_memory, MaterialGpu, mats.items);

    // Spheres buffer (always at least 1 entry to keep binding valid)
    const sphere_size: u64 = @max(@sizeOf(SphereGpu), @sizeOf(SphereGpu) * spheres.items.len);
    try createHostBuffer(app, sphere_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.sphere_buffer, &app.sphere_memory);
    try uploadHostBuffer(app, app.sphere_memory, SphereGpu, spheres.items);

    // Quads buffer
    const quad_size: u64 = @max(@sizeOf(QuadGpu), @sizeOf(QuadGpu) * quads.items.len);
    try createHostBuffer(app, quad_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.quad_buffer, &app.quad_memory);
    try uploadHostBuffer(app, app.quad_memory, QuadGpu, quads.items);

    // Lights buffer (always at least 1 entry)
    const light_size: u64 = @max(@sizeOf(QuadGpu), @sizeOf(QuadGpu) * lights.items.len);
    try createHostBuffer(app, light_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.light_buffer, &app.light_memory);
    if (lights.items.len > 0) {
        try uploadHostBuffer(app, app.light_memory, QuadGpu, lights.items);
    } else {
        var dummy = [_]QuadGpu{.{
            .q = .{ 0, 0, 0, 0 },
            .u = .{ 0, 0, 0, 0 },
            .v = .{ 0, 0, 0, 0 },
            .n_d = .{ 0, 0, 0, 0 },
            .w_vec = .{ 0, 0, 0, 0 },
            .mat_pad = .{ 0, 0, 0, 0 },
        }};
        try uploadHostBuffer(app, app.light_memory, QuadGpu, &dummy);
    }

    // Build BVH on (spheres + quads), upload bvh nodes + prim refs
    var bvh_nodes: std.ArrayList(BvhNodeGpu) = .empty;
    defer bvh_nodes.deinit(app.alloc);
    var prim_refs: std.ArrayList(u32) = .empty;
    defer prim_refs.deinit(app.alloc);
    try buildBvh(app, spheres.items, quads.items, &bvh_nodes, &prim_refs);

    app.bvh_node_count = @intCast(bvh_nodes.items.len);
    app.primref_count = @intCast(prim_refs.items.len);
    std.debug.print("BVH: {d} nodes, {d} prim refs\n", .{ bvh_nodes.items.len, prim_refs.items.len });

    const bvh_size: u64 = @max(@sizeOf(BvhNodeGpu), @sizeOf(BvhNodeGpu) * bvh_nodes.items.len);
    try createHostBuffer(app, bvh_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.bvh_buffer, &app.bvh_memory);
    try uploadHostBuffer(app, app.bvh_memory, BvhNodeGpu, bvh_nodes.items);

    const ref_size: u64 = @max(@sizeOf(u32), @sizeOf(u32) * prim_refs.items.len);
    try createHostBuffer(app, ref_size, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, &app.primref_buffer, &app.primref_memory);
    if (prim_refs.items.len > 0) {
        try uploadHostBuffer(app, app.primref_memory, u32, prim_refs.items);
    } else {
        var dummy = [_]u32{0};
        try uploadHostBuffer(app, app.primref_memory, u32, &dummy);
    }
}

fn destroySceneBuffers(app: *App) void {
    c.vkDestroyBuffer(app.device, app.material_buffer, null);
    c.vkFreeMemory(app.device, app.material_memory, null);
    c.vkDestroyBuffer(app.device, app.sphere_buffer, null);
    c.vkFreeMemory(app.device, app.sphere_memory, null);
    c.vkDestroyBuffer(app.device, app.quad_buffer, null);
    c.vkFreeMemory(app.device, app.quad_memory, null);
    c.vkDestroyBuffer(app.device, app.light_buffer, null);
    c.vkFreeMemory(app.device, app.light_memory, null);
    c.vkDestroyBuffer(app.device, app.bvh_buffer, null);
    c.vkFreeMemory(app.device, app.bvh_memory, null);
    c.vkDestroyBuffer(app.device, app.primref_buffer, null);
    c.vkFreeMemory(app.device, app.primref_memory, null);
}

// -----------------------------------------------------------------------------
// Uniform buffer
// -----------------------------------------------------------------------------

fn createUniformBuffer(app: *App) !void {
    const buffer_ci: c.VkBufferCreateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = @sizeOf(CameraUbo),
        .usage = c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        .sharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
    };
    try vkCheck(c.vkCreateBuffer(app.device, &buffer_ci, null, &app.ubo_buffer));

    var mem_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(app.device, app.ubo_buffer, &mem_req);

    const mem_type = try findMemoryType(
        app,
        mem_req.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    );
    const ai: c.VkMemoryAllocateInfo = .{
        .sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = mem_req.size,
        .memoryTypeIndex = mem_type,
    };
    try vkCheck(c.vkAllocateMemory(app.device, &ai, null, &app.ubo_memory));
    try vkCheck(c.vkBindBufferMemory(app.device, app.ubo_buffer, app.ubo_memory, 0));

    var raw: ?*anyopaque = null;
    try vkCheck(c.vkMapMemory(app.device, app.ubo_memory, 0, @sizeOf(CameraUbo), 0, &raw));
    app.ubo_mapped = @ptrCast(@alignCast(raw.?));
}

fn destroyUniformBuffer(app: *App) void {
    c.vkUnmapMemory(app.device, app.ubo_memory);
    c.vkDestroyBuffer(app.device, app.ubo_buffer, null);
    c.vkFreeMemory(app.device, app.ubo_memory, null);
}

fn cameraChanged(a: Camera, b: Camera) bool {
    inline for (0..3) |i| if (a.lookfrom[i] != b.lookfrom[i]) return true;
    inline for (0..3) |i| if (a.lookat[i] != b.lookat[i]) return true;
    inline for (0..3) |i| if (a.vup[i] != b.vup[i]) return true;
    if (a.vfov_deg != b.vfov_deg) return true;
    return false;
}

fn updateUbo(app: *App) void {
    if (cameraChanged(app.camera, app.prev_camera)) {
        app.accum_index = 0;
        app.prev_camera = app.camera;
    }

    const w_f: f32 = @floatFromInt(app.swapchain_extent.width);
    const h_f: f32 = @floatFromInt(app.swapchain_extent.height);
    app.ubo_mapped.* = .{
        .lookfrom = .{ app.camera.lookfrom[0], app.camera.lookfrom[1], app.camera.lookfrom[2], 0 },
        .lookat_vfov = .{ app.camera.lookat[0], app.camera.lookat[1], app.camera.lookat[2], app.camera.vfov_deg * std.math.pi / 180.0 },
        .vup_aspect = .{ app.camera.vup[0], app.camera.vup[1], app.camera.vup[2], w_f / h_f },
        .frame_size = .{ app.swapchain_extent.width, app.swapchain_extent.height, app.camera.frame_idx, 0 },
        .counts = .{ app.sphere_count, app.quad_count, app.material_count, app.accum_index },
        .extra = .{ app.light_count, 0, 0, 0 },
    };
    app.camera.frame_idx +%= 1;
    app.accum_index +%= 1;
}

// -----------------------------------------------------------------------------
// Camera input (WASD + right-click look)
// -----------------------------------------------------------------------------

const move_speed_units_per_sec: f32 = 250.0;
const mouse_sensitivity: f32 = 0.0025;
const pitch_clamp: f32 = 1.5533;

fn updateCamera(app: *App) void {
    const now = c.glfwGetTime();
    const dt: f32 = @floatCast(now - app.last_time);
    app.last_time = now;

    // mouse look (right-click held)
    var mouse_x: f64 = 0;
    var mouse_y: f64 = 0;
    c.glfwGetCursorPos(app.window, &mouse_x, &mouse_y);
    const right_pressed = c.glfwGetMouseButton(app.window, c.GLFW_MOUSE_BUTTON_RIGHT) == c.GLFW_PRESS;
    if (right_pressed) {
        if (!app.looking) {
            // just started looking; sync prev to avoid jump
            app.prev_mouse_x = mouse_x;
            app.prev_mouse_y = mouse_y;
            _ = c.glfwSetInputMode(app.window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
            app.looking = true;
        }
        const dx: f32 = @floatCast(mouse_x - app.prev_mouse_x);
        const dy: f32 = @floatCast(mouse_y - app.prev_mouse_y);
        app.prev_mouse_x = mouse_x;
        app.prev_mouse_y = mouse_y;
        app.camera.yaw -= dx * mouse_sensitivity;
        app.camera.pitch -= dy * mouse_sensitivity;
        if (app.camera.pitch > pitch_clamp) app.camera.pitch = pitch_clamp;
        if (app.camera.pitch < -pitch_clamp) app.camera.pitch = -pitch_clamp;
    } else if (app.looking) {
        _ = c.glfwSetInputMode(app.window, c.GLFW_CURSOR, c.GLFW_CURSOR_NORMAL);
        app.looking = false;
    }

    // forward from yaw/pitch
    const cp = @cos(app.camera.pitch);
    const sp = @sin(app.camera.pitch);
    const cy = @cos(app.camera.yaw);
    const sy = @sin(app.camera.yaw);
    const forward = [3]f32{ cp * sy, sp, cp * cy };
    const world_up = [3]f32{ 0, 1, 0 };
    const right = normalize3(cross3(forward, world_up));

    const speed = move_speed_units_per_sec * dt;
    var dx: f32 = 0;
    var dy: f32 = 0;
    var dz: f32 = 0;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_W) == c.GLFW_PRESS) dz += 1;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_S) == c.GLFW_PRESS) dz -= 1;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_D) == c.GLFW_PRESS) dx += 1;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_A) == c.GLFW_PRESS) dx -= 1;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_E) == c.GLFW_PRESS) dy += 1;
    if (c.glfwGetKey(app.window, c.GLFW_KEY_Q) == c.GLFW_PRESS) dy -= 1;

    app.camera.lookfrom[0] += (forward[0] * dz + right[0] * dx + world_up[0] * dy) * speed;
    app.camera.lookfrom[1] += (forward[1] * dz + right[1] * dx + world_up[1] * dy) * speed;
    app.camera.lookfrom[2] += (forward[2] * dz + right[2] * dx + world_up[2] * dy) * speed;

    app.camera.lookat[0] = app.camera.lookfrom[0] + forward[0] * 100.0;
    app.camera.lookat[1] = app.camera.lookfrom[1] + forward[1] * 100.0;
    app.camera.lookat[2] = app.camera.lookfrom[2] + forward[2] * 100.0;
}

fn readShaderFile(app: *App, rel_path: []const u8) ![]align(4) u8 {
    var exe_buf: [4096]u8 = undefined;
    const exe_len = try std.process.executableDirPath(app.io, &exe_buf);
    const exe_path = exe_buf[0..exe_len];

    const full = try std.fs.path.join(app.alloc, &.{ exe_path, rel_path });
    defer app.alloc.free(full);

    const file = try std.Io.Dir.openFileAbsolute(app.io, full, .{});
    defer file.close(app.io);
    const stat = try file.stat(app.io);
    const buf = try app.alloc.alignedAlloc(u8, .@"4", stat.size);
    _ = try file.readPositionalAll(app.io, buf, 0);
    return buf;
}
