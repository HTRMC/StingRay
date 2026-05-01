const std = @import("std");

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
            const r = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(image_width - 1));
            const g = @as(f64, @floatFromInt(j)) / @as(f64, @floatFromInt(image_height - 1));
            const b = 0.0;

            const ir: u8 = @intFromFloat(255.0 * r);
            const ig: u8 = @intFromFloat(255.0 * g);
            const ib: u8 = @intFromFloat(255.0 * b);

            try stdout.print("{} {} {}\n", .{ ir, ig, ib });
        }
    }

    try stderr.print("\rDone.                 \n", .{});
}
