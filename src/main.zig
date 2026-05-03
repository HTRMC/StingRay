const std = @import("std");
const color_mod = @import("color.zig");
const Vec3 = color_mod.Vec3;
const Color = color_mod.Color;
const Sphere = @import("sphere.zig").Sphere;
const Quad = @import("quad.zig").Quad;
const Hittable = @import("hittable.zig").Hittable;
const HittableList = @import("hittable_list.zig").HittableList;
const Camera = @import("camera.zig").Camera;
const BvhNode = @import("bvh.zig").BvhNode;
const material_mod = @import("material.zig");
const Material = material_mod.Material;
const Metal = material_mod.Metal;
const texture_mod = @import("texture.zig");
const Texture = texture_mod.Texture;
const Checker = texture_mod.Checker;
const ImageTexture = texture_mod.ImageTexture;
const NoiseTexture = texture_mod.NoiseTexture;
const Image = @import("image.zig").Image;
const Perlin = @import("perlin.zig").Perlin;
const random = @import("random.zig");

const Scene = enum { bouncing_spheres, checkered_spheres, earth, perlin_spheres, quads };
const selected_scene: Scene = .quads;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    switch (selected_scene) {
        .bouncing_spheres => try bouncingSpheres(stdout, stderr),
        .checkered_spheres => try checkeredSpheres(stdout, stderr),
        .earth => try earth(stdout, stderr),
        .perlin_spheres => try perlinSpheres(stdout, stderr),
        .quads => try quads(stdout, stderr),
    }
}

fn quads(stdout: anytype, stderr: anytype) !void {
    const allocator = std.heap.page_allocator;
    var world = HittableList.init(allocator);
    defer world.deinit();

    const left_red: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(1.0, 0.2, 0.2)) };
    const back_green: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(0.2, 1.0, 0.2)) };
    const right_blue: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(0.2, 0.2, 1.0)) };
    const upper_orange: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(1.0, 0.5, 0.0)) };
    const lower_teal: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(0.2, 0.8, 0.8)) };

    try world.add(.{ .quad = Quad.init(Vec3.init(-3, -2, 5), Vec3.init(0, 0, -4), Vec3.init(0, 4, 0), left_red) });
    try world.add(.{ .quad = Quad.init(Vec3.init(-2, -2, 0), Vec3.init(4, 0, 0), Vec3.init(0, 4, 0), back_green) });
    try world.add(.{ .quad = Quad.init(Vec3.init(3, -2, 1), Vec3.init(0, 0, 4), Vec3.init(0, 4, 0), right_blue) });
    try world.add(.{ .quad = Quad.init(Vec3.init(-2, 3, 1), Vec3.init(4, 0, 0), Vec3.init(0, 0, 4), upper_orange) });
    try world.add(.{ .quad = Quad.init(Vec3.init(-2, -3, 5), Vec3.init(4, 0, 0), Vec3.init(0, 0, -4), lower_teal) });

    var cam: Camera = .{};
    cam.aspect_ratio = 1.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;
    cam.vfov = 80;
    cam.lookfrom = Vec3.init(0, 0, 9);
    cam.lookat = Vec3.init(0, 0, 0);
    cam.vup = Vec3.init(0, 1, 0);
    cam.defocus_angle = 0;

    try cam.render(world, stdout, stderr);
}

fn perlinSpheres(stdout: anytype, stderr: anytype) !void {
    const allocator = std.heap.page_allocator;
    var world = HittableList.init(allocator);
    defer world.deinit();

    const perlin_noise = try allocator.create(Perlin);
    perlin_noise.* = Perlin.init();
    const noise_tex: Texture = .{ .noise = NoiseTexture.init(perlin_noise, 4) };
    const noise_material: Material = .{ .lambertian = material_mod.Lambertian.fromTexture(noise_tex) };

    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -1000, 0), 1000, noise_material) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 2, 0), 2, noise_material) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;
    cam.vfov = 20;
    cam.lookfrom = Vec3.init(13, 2, 3);
    cam.lookat = Vec3.init(0, 0, 0);
    cam.vup = Vec3.init(0, 1, 0);
    cam.defocus_angle = 0;

    try cam.render(world, stdout, stderr);
}

fn bouncingSpheres(stdout: anytype, stderr: anytype) !void {
    var world = HittableList.init(std.heap.page_allocator);
    defer world.deinit();

    const ground_material: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(0.5, 0.5, 0.5)) };
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
                const sphere_material: Material = .{ .lambertian = material_mod.Lambertian.fromColor(albedo) };
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

    const material2: Material = .{ .lambertian = material_mod.Lambertian.fromColor(Color.init(0.4, 0.2, 0.1)) };
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

fn earth(stdout: anytype, stderr: anytype) !void {
    const allocator = std.heap.page_allocator;
    var world = HittableList.init(allocator);
    defer world.deinit();

    const earth_image = try allocator.create(Image);
    earth_image.* = Image.load("earthmap.jpg");
    const earth_tex: Texture = .{ .image = ImageTexture.init(earth_image) };
    const earth_surface: Material = .{ .lambertian = material_mod.Lambertian.fromTexture(earth_tex) };

    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 0, 0), 2, earth_surface) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;
    cam.vfov = 20;
    cam.lookfrom = Vec3.init(0, 0, 12);
    cam.lookat = Vec3.init(0, 0, 0);
    cam.vup = Vec3.init(0, 1, 0);
    cam.defocus_angle = 0;

    try cam.render(world, stdout, stderr);
}

fn checkeredSpheres(stdout: anytype, stderr: anytype) !void {
    const allocator = std.heap.page_allocator;
    var world = HittableList.init(allocator);
    defer world.deinit();

    const even_tex = try allocator.create(Texture);
    even_tex.* = Texture.fromColor(Color.init(0.2, 0.3, 0.1));
    const odd_tex = try allocator.create(Texture);
    odd_tex.* = Texture.fromColor(Color.init(0.9, 0.9, 0.9));
    const checker_tex: Texture = .{ .checker = Checker.init(0.32, even_tex, odd_tex) };
    const checker_material: Material = .{ .lambertian = material_mod.Lambertian.fromTexture(checker_tex) };

    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -10, 0), 10, checker_material) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 10, 0), 10, checker_material) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;
    cam.vfov = 20;
    cam.lookfrom = Vec3.init(13, 2, 3);
    cam.lookat = Vec3.init(0, 0, 0);
    cam.vup = Vec3.init(0, 1, 0);
    cam.defocus_angle = 0;

    try cam.render(world, stdout, stderr);
}
