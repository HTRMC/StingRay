const std = @import("std");
const color_mod = @import("color.zig");
const Vec3 = color_mod.Vec3;
const Color = color_mod.Color;
const Sphere = @import("sphere.zig").Sphere;
const Hittable = @import("hittable.zig").Hittable;
const HittableList = @import("hittable_list.zig").HittableList;
const Camera = @import("camera.zig").Camera;
const BvhNode = @import("bvh.zig").BvhNode;
const material_mod = @import("material.zig");
const Material = material_mod.Material;
const Metal = material_mod.Metal;
const random = @import("random.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    var world = HittableList.init(std.heap.page_allocator);
    defer world.deinit();

    const ground_material: Material = .{ .lambertian = .{ .albedo = Color.init(0.5, 0.5, 0.5) } };
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -1000, 0), 1000, ground_material) });

    var a: i32 = -11;
    while (a < 11) : (a += 1) {
        var b: i32 = -11;
        while (b < 11) : (b += 1) {
            const choose_mat = random.float();
            const af: f32 = @floatFromInt(a);
            const bf: f32 = @floatFromInt(b);
            const center = Vec3.init(af + 0.9 * random.float(), 0.2, bf + 0.9 * random.float());

            if (center.sub(Vec3.init(4, 0.2, 0)).length() <= 0.9) continue;

            if (choose_mat < 0.8) {
                const albedo = color_mod.hadamard(random.vec(), random.vec());
                const sphere_material: Material = .{ .lambertian = .{ .albedo = albedo } };
                const center2 = center.add(Vec3.init(0, random.floatRange(0, 0.5), 0));
                try world.add(.{ .sphere = Sphere.initMoving(center, center2, 0.2, sphere_material) });
            } else if (choose_mat < 0.95) {
                const albedo = random.vecRange(0.5, 1);
                const fuzz = random.floatRange(0, 0.5);
                const sphere_material: Material = .{ .metal = Metal.init(albedo, fuzz) };
                try world.add(.{ .sphere = Sphere.init(center, 0.2, sphere_material) });
            } else {
                const sphere_material: Material = .{ .dielectric = .{ .refraction_index = 1.5 } };
                try world.add(.{ .sphere = Sphere.init(center, 0.2, sphere_material) });
            }
        }
    }

    const material1: Material = .{ .dielectric = .{ .refraction_index = 1.5 } };
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 1, 0), 1.0, material1) });

    const material2: Material = .{ .lambertian = .{ .albedo = Color.init(0.4, 0.2, 0.1) } };
    try world.add(.{ .sphere = Sphere.init(Vec3.init(-4, 1, 0), 1.0, material2) });

    const material3: Material = .{ .metal = Metal.init(Color.init(0.7, 0.6, 0.5), 0.0) };
    try world.add(.{ .sphere = Sphere.init(Vec3.init(4, 1, 0), 1.0, material3) });

    const bvh = try BvhNode.fromList(std.heap.page_allocator, world);
    world.clear();
    try world.add(.{ .bvh_node = bvh });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 1200;
    cam.samples_per_pixel = 500;
    cam.max_depth = 50;
    cam.vfov = 20;
    cam.lookfrom = Vec3.init(13, 2, 3);
    cam.lookat = Vec3.init(0, 0, 0);
    cam.vup = Vec3.init(0, 1, 0);
    cam.defocus_angle = 0.6;
    cam.focus_dist = 10.0;

    try cam.render(world, stdout, stderr);
}
