const std = @import("std");
const zlm = @import("zlm").init(.{ .graphics_api = .opengl, .shader_lang = .glsl });
const Interval = @import("interval.zig").Interval;

pub const Vec3 = zlm.Vec3(f64);
pub const Color = Vec3;

pub fn nearZero(v: Vec3) bool {
    const epsilon: f64 = 1e-8;
    return @abs(v.x) < epsilon and @abs(v.y) < epsilon and @abs(v.z) < epsilon;
}

pub fn hadamard(a: Vec3, b: Vec3) Vec3 {
    return Vec3.init(a.x * b.x, a.y * b.y, a.z * b.z);
}

pub fn write_color(writer: anytype, pixel_color: Color) !void {
    const r_raw = if (pixel_color.x != pixel_color.x) 0 else pixel_color.x;
    const g_raw = if (pixel_color.y != pixel_color.y) 0 else pixel_color.y;
    const b_raw = if (pixel_color.z != pixel_color.z) 0 else pixel_color.z;

    const r = linearToGamma(r_raw);
    const g = linearToGamma(g_raw);
    const b = linearToGamma(b_raw);

    const intensity = Interval.init(0.000, 0.999);
    const rbyte: i32 = @intFromFloat(256.0 * intensity.clamp(r));
    const gbyte: i32 = @intFromFloat(256.0 * intensity.clamp(g));
    const bbyte: i32 = @intFromFloat(256.0 * intensity.clamp(b));

    try writer.print("{} {} {}\n", .{ rbyte, gbyte, bbyte });
}

fn linearToGamma(linear: f64) f64 {
    if (linear > 0) return @sqrt(linear);
    return 0;
}
