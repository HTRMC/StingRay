const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const Sphere = @import("sphere.zig").Sphere;

pub const HitRecord = struct {
    point: Vec3,
    normal: Vec3,
    hit_t: f32,
};

pub const Hittable = union(enum) {
    sphere: Sphere,

    pub fn hit(self: Hittable, ray: Ray, ray_tmin: f32, ray_tmax: f32, record: *HitRecord) bool {
        return switch (self) {
            inline else => |obj| obj.hit(ray, ray_tmin, ray_tmax, record),
        };
    }
};
