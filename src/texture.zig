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

pub const Texture = union(enum) {
    solid: SolidColor,

    pub fn fromColor(albedo: Color) Texture {
        return .{ .solid = SolidColor.init(albedo) };
    }

    pub fn value(self: Texture, u: f32, v: f32, p: Vec3) Color {
        return switch (self) {
            inline else => |variant| variant.value(u, v, p),
        };
    }
};
