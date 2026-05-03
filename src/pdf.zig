const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Onb = @import("onb.zig").Onb;
const random = @import("random.zig");

pub const SpherePdf = struct {
    pub fn value(self: SpherePdf, direction: Vec3) f32 {
        _ = self;
        _ = direction;
        return 1.0 / (4.0 * std.math.pi);
    }

    pub fn generate(self: SpherePdf) Vec3 {
        _ = self;
        return random.unitVector();
    }
};

pub const CosinePdf = struct {
    basis: Onb,

    pub fn init(w: Vec3) CosinePdf {
        return .{ .basis = Onb.init(w) };
    }

    pub fn value(self: CosinePdf, direction: Vec3) f32 {
        const cos_theta = direction.normalize().dot(self.basis.w());
        return @max(0, cos_theta / std.math.pi);
    }

    pub fn generate(self: CosinePdf) Vec3 {
        return self.basis.transform(random.cosineDirection());
    }
};

pub const Pdf = union(enum) {
    sphere: SpherePdf,
    cosine: CosinePdf,

    pub fn value(self: Pdf, direction: Vec3) f32 {
        return switch (self) {
            inline else => |variant| variant.value(direction),
        };
    }

    pub fn generate(self: Pdf) Vec3 {
        return switch (self) {
            inline else => |variant| variant.generate(),
        };
    }
};
