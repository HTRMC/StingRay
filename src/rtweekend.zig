const std = @import("std");

pub const infinity: f32 = std.math.inf(f32);
pub const pi: f32 = std.math.pi;

pub fn degreesToRadians(degrees: f32) f32 {
    return degrees * pi / 180.0;
}
