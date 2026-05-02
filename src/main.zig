const std = @import("std");
const color_mod = @import("color.zig");
const Vec3 = color_mod.Vec3;
const Color = color_mod.Color;
const Sphere = @import("sphere.zig").Sphere;
const Hittable = @import("hittable.zig").Hittable;
const HittableList = @import("hittable_list.zig").HittableList;
const Camera = @import("camera.zig").Camera;
const material_mod = @import("material.zig");
const Material = material_mod.Material;
const Metal = material_mod.Metal;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    var world = HittableList.init(std.heap.page_allocator);
    defer world.deinit();

    const material_ground: Material = .{ .lambertian = .{ .albedo = Color.init(0.8, 0.8, 0.0) } };
    const material_center: Material = .{ .lambertian = .{ .albedo = Color.init(0.1, 0.2, 0.5) } };
    const material_left: Material = .{ .dielectric = .{ .refraction_index = 1.5 } };
    const material_bubble: Material = .{ .dielectric = .{ .refraction_index = 1.0 / 1.5 } };
    const material_right: Material = .{ .metal = Metal.init(Color.init(0.8, 0.6, 0.2), 1.0) };

    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -100.5, -1), 100, material_ground) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 0, -1.2), 0.5, material_center) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(-1, 0, -1), 0.5, material_left) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(-1, 0, -1), 0.4, material_bubble) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(1, 0, -1), 0.5, material_right) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;
    cam.vfov = 20;
    cam.lookfrom = Vec3.init(-2, 2, 1);
    cam.lookat = Vec3.init(0, 0, -1);
    cam.vup = Vec3.init(0, 1, 0);

    try cam.render(world, stdout, stderr);
}
