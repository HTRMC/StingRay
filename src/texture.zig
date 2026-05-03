const std = @import("std");
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const Vec3 = color_mod.Vec3;

pub const SolidColor = struct {
    albedo: Color,

    pub fn init(albedo: Color) SolidColor {
        return .{ .albedo = albedo };
    }

    pub fn value(self: SolidColor, u: f32, v: f32, p: Vec3) Color {
        _ = u;
        _ = v;
        _ = p;
        return self.albedo;
    }
};

pub const Checker = struct {
    inv_scale: f32,
    even: *const Texture,
    odd: *const Texture,

    pub fn init(scale: f32, even: *const Texture, odd: *const Texture) Checker {
        return .{ .inv_scale = 1.0 / scale, .even = even, .odd = odd };
    }

    pub fn value(self: Checker, u: f32, v: f32, p: Vec3) Color {
        const x_int: i32 = @intFromFloat(@floor(self.inv_scale * p.x));
        const y_int: i32 = @intFromFloat(@floor(self.inv_scale * p.y));
        const z_int: i32 = @intFromFloat(@floor(self.inv_scale * p.z));
        const is_even = @mod(x_int + y_int + z_int, 2) == 0;
        return if (is_even) self.even.value(u, v, p) else self.odd.value(u, v, p);
    }
};

pub const Texture = union(enum) {
    solid: SolidColor,
    checker: Checker,

    pub fn fromColor(albedo: Color) Texture {
        return .{ .solid = SolidColor.init(albedo) };
    }

    pub fn value(self: Texture, u: f32, v: f32, p: Vec3) Color {
        return switch (self) {
            inline else => |variant| variant.value(u, v, p),
        };
    }
};
