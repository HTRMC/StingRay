const std = @import("std");
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const Vec3 = color_mod.Vec3;
const Image = @import("image.zig").Image;
const Interval = @import("interval.zig").Interval;
const Perlin = @import("perlin.zig").Perlin;

pub const SolidColor = struct {
    albedo: Color,

    pub fn init(albedo: Color) SolidColor {
        return .{ .albedo = albedo };
    }

    pub fn value(self: SolidColor, u: f64, v: f64, p: Vec3) Color {
        _ = u;
        _ = v;
        _ = p;
        return self.albedo;
    }
};

pub const Checker = struct {
    inv_scale: f64,
    even: *const Texture,
    odd: *const Texture,

    pub fn init(scale: f64, even: *const Texture, odd: *const Texture) Checker {
        return .{ .inv_scale = 1.0 / scale, .even = even, .odd = odd };
    }

    pub fn value(self: Checker, u: f64, v: f64, p: Vec3) Color {
        const x_int: i32 = @intFromFloat(@floor(self.inv_scale * p.x));
        const y_int: i32 = @intFromFloat(@floor(self.inv_scale * p.y));
        const z_int: i32 = @intFromFloat(@floor(self.inv_scale * p.z));
        const is_even = @mod(x_int + y_int + z_int, 2) == 0;
        return if (is_even) self.even.value(u, v, p) else self.odd.value(u, v, p);
    }
};

pub const ImageTexture = struct {
    image: *const Image,

    pub fn init(image: *const Image) ImageTexture {
        return .{ .image = image };
    }

    pub fn value(self: ImageTexture, u: f64, v: f64, p: Vec3) Color {
        _ = p;
        if (self.image.height <= 0) return Color.init(0, 1, 1);

        const unit = Interval.init(0, 1);
        const u_clamped = unit.clamp(u);
        const v_clamped = 1.0 - unit.clamp(v);

        const w_f: f64 = @floatFromInt(self.image.width);
        const h_f: f64 = @floatFromInt(self.image.height);
        const i: i32 = @intFromFloat(u_clamped * w_f);
        const j: i32 = @intFromFloat(v_clamped * h_f);
        const px = self.image.pixel(i, j);

        const scale_byte = 1.0 / 255.0;
        return Color.init(
            @as(f64, @floatFromInt(px[0])) * scale_byte,
            @as(f64, @floatFromInt(px[1])) * scale_byte,
            @as(f64, @floatFromInt(px[2])) * scale_byte,
        );
    }
};

pub const NoiseTexture = struct {
    noise: *const Perlin,
    scale: f64,

    pub fn init(noise: *const Perlin, scale: f64) NoiseTexture {
        return .{ .noise = noise, .scale = scale };
    }

    pub fn value(self: NoiseTexture, u: f64, v: f64, p: Vec3) Color {
        _ = u;
        _ = v;
        const phase = self.scale * p.z + 10.0 * self.noise.turb(p, 7);
        return Color.init(0.5, 0.5, 0.5).scale(1.0 + @sin(phase));
    }
};

pub const Texture = union(enum) {
    solid: SolidColor,
    checker: Checker,
    image: ImageTexture,
    noise: NoiseTexture,

    pub fn fromColor(albedo: Color) Texture {
        return .{ .solid = SolidColor.init(albedo) };
    }

    pub fn value(self: Texture, u: f64, v: f64, p: Vec3) Color {
        return switch (self) {
            inline else => |variant| variant.value(u, v, p),
        };
    }
};
