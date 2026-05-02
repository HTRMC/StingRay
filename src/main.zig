const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Sphere = @import("sphere.zig").Sphere;
const Hittable = @import("hittable.zig").Hittable;
const HittableList = @import("hittable_list.zig").HittableList;
const Camera = @import("camera.zig").Camera;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    var world = HittableList.init(std.heap.page_allocator);
    defer world.deinit();
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, 0, -1), 0.5) });
    try world.add(.{ .sphere = Sphere.init(Vec3.init(0, -100.5, -1), 100) });

    var cam: Camera = .{};
    cam.aspect_ratio = 16.0 / 9.0;
    cam.image_width = 400;
    cam.samples_per_pixel = 100;
    cam.max_depth = 50;

    try cam.render(world, stdout, stderr);
}
