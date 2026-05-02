const Ray = @import("ray.zig").Ray;
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const HitRecord = @import("hittable.zig").HitRecord;
const random = @import("random.zig");

pub const Lambertian = struct {
    albedo: Color,

    pub fn scatter(
        self: Lambertian,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        _ = ray_in;
        var direction = record.normal.add(random.unitVector());
        if (color_mod.nearZero(direction)) direction = record.normal;
        scattered.* = Ray.init(record.point, direction);
        attenuation.* = self.albedo;
        return true;
    }
};

pub const Metal = struct {
    albedo: Color,

    pub fn scatter(
        self: Metal,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        const reflected = ray_in.direction().reflect(record.normal);
        scattered.* = Ray.init(record.point, reflected);
        attenuation.* = self.albedo;
        return true;
    }
};

pub const Material = union(enum) {
    none: void,
    lambertian: Lambertian,
    metal: Metal,

    pub fn scatter(
        self: Material,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        return switch (self) {
            .none => false,
            inline else => |variant| variant.scatter(ray_in, record, attenuation, scattered),
        };
    }
};
