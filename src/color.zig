const std = @import("std");
const zlm = @import("zlm").init(.{ .graphics_api = .opengl, .shader_lang = .glsl });
const Interval = @import("interval.zig").Interval;

pub const Vec3 = zlm.Vec3(f32);
pub const Color = Vec3;

pub fn write_color(writer: anytype, pixel_color: Color) !void {
    const r = linearToGamma(pixel_color.x);
    const g = linearToGamma(pixel_color.y);
    const b = linearToGamma(pixel_color.z);

    const intensity = Interval.init(0.000, 0.999);
    const rbyte: i32 = @intFromFloat(256.0 * intensity.clamp(r));
    const gbyte: i32 = @intFromFloat(256.0 * intensity.clamp(g));
    const bbyte: i32 = @intFromFloat(256.0 * intensity.clamp(b));

    try writer.print("{} {} {}\n", .{ rbyte, gbyte, bbyte });
}

fn linearToGamma(linear: f32) f32 {
    if (linear > 0) return @sqrt(linear);
    return 0;
}
