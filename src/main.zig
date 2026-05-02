const std = @import("std");
const color_mod = @import("color.zig");
const Vec3 = color_mod.Vec3;
const Color = color_mod.Color;
const Sphere = @import("sphere.zig").Sphere;
const Hittable = @import("hittable.zig").Hittable;
const HittableList = @import("hittable_list.zig").HittableList;
const Camera = @import("camera.zig").Camera;
const Material = @import("material.zig").Material;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    var world = HittableList.init(std.heap.page_allocator);
    defer world.deinit();
    const placeholder: Material = .{ .lambertian = .{ .albedo = Color.init(0.5, 0.5, 0.5) } };
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 0, -1), 0.5, placeholder) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -100.5, -1), 100, placeholder) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;

    try cam.render(world, stdout, stderr);
}
