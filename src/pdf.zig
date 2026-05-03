const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Onb = @import("onb.zig").Onb;
const random = @import("random.zig");
const Hittable = @import("hittable.zig").Hittable;

pub const SpherePdf = struct {
    pub fn value(self: SpherePdf, direction: Vec3) f64 {
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

    pub fn value(self: CosinePdf, direction: Vec3) f64 {
        const cos_theta = direction.normalize().dot(self.basis.w());
        return @max(0, cos_theta / std.math.pi);
    }

    pub fn generate(self: CosinePdf) Vec3 {
        return self.basis.transform(random.cosineDirection());
    }
};

pub const HittablePdf = struct {
    object: *const Hittable,
    origin: Vec3,

    pub fn init(object: *const Hittable, origin: Vec3) HittablePdf {
        return .{ .object = object, .origin = origin };
    }

    pub fn value(self: HittablePdf, direction: Vec3) f64 {
        return self.object.pdfValue(self.origin, direction);
    }

    pub fn generate(self: HittablePdf) Vec3 {
        return self.object.randomToward(self.origin);
    }
};

pub const MixturePdf = struct {
    p0: *const Pdf,
    p1: *const Pdf,

    pub fn init(p0: *const Pdf, p1: *const Pdf) MixturePdf {
        return .{ .p0 = p0, .p1 = p1 };
    }

    pub fn value(self: MixturePdf, direction: Vec3) f64 {
        return 0.5 * self.p0.value(direction) + 0.5 * self.p1.value(direction);
    }

    pub fn generate(self: MixturePdf) Vec3 {
        if (random.float() < 0.5) return self.p0.generate();
        return self.p1.generate();
    }
};

pub const Pdf = union(enum) {
    sphere: SpherePdf,
    cosine: CosinePdf,
    hittable: HittablePdf,
    mixture: MixturePdf,

    pub fn value(self: Pdf, direction: Vec3) f64 {
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
