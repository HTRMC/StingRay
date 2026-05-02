const Ray = @import("ray.zig").Ray;
const Color = @import("color.zig").Color;
const HitRecord = @import("hittable.zig").HitRecord;

pub const Material = union(enum) {
    none: void,

    pub fn scatter(
        self: Material,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        _ = self;
        _ = ray_in;
        _ = record;
        _ = attenuation;
        _ = scattered;
        return false;
    }
};
