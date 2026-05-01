const std = @import("std");
const zlm = @import("zlm").init(.{ .graphics_api = .opengl, .shader_lang = .glsl });

pub const Vec3 = zlm.Vec3(f32);
pub const Color = Vec3;

pub fn write_color(writer: anytype, pixel_color: Color) !void {
    const r = pixel_color.x;
    const g = pixel_color.y;
    const b = pixel_color.z;

    // Convert [0,1] → [0,255]
    const rbyte: i32 = @intFromFloat(255.999 * r);
    const gbyte: i32 = @intFromFloat(255.999 * g);
    const bbyte: i32 = @intFromFloat(255.999 * b);

    try writer.print("{} {} {}\n", .{ rbyte, gbyte, bbyte });
}
