const std = @import("std");
const color = @import("color.zig");
const Color = color.Color;
const write_color = color.write_color;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    const image_width: u16 = 256;
    const image_height: u16 = 256;

    try stdout.print("P3\n{} {}\n255\n", .{ image_width, image_height });

    for (0..image_height) |j| {
        try stderr.print("\rScanlines remaining: {}", .{image_height - j});
        for (0..image_width) |i| {
            const fi: f32 = @floatFromInt(i);
            const fj: f32 = @floatFromInt(j);
            const pixel_color = Color.init(
                fi / @as(f32, image_width - 1),
                fj / @as(f32, image_height - 1),
                0.0,
            );
            try write_color(stdout, pixel_color);
        }
    }

    try stderr.print("\rDone.                 \n", .{});
}
