const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const Interval = @import("interval.zig").Interval;

pub const Sphere = struct {
    center: Vec3,
    radius: f32,

    pub fn init(center: Vec3, radius: f32) Sphere {
        return .{ .center = center, .radius = @max(0, radius) };
    }

    pub fn hit(self: Sphere, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        const origin_to_center = self.center.sub(ray.origin());
        const quadratic_a = ray.direction().dot(ray.direction());
        const half_b = ray.direction().dot(origin_to_center);
        const quadratic_c = origin_to_center.dot(origin_to_center) - self.radius * self.radius;

        const discriminant = half_b * half_b - quadratic_a * quadratic_c;
        if (discriminant < 0) return false;

        const sqrt_disc = @sqrt(discriminant);

        var root = (half_b - sqrt_disc) / quadratic_a;
        if (!ray_t.surrounds(root)) {
            root = (half_b + sqrt_disc) / quadratic_a;
            if (!ray_t.surrounds(root)) return false;
        }

        record.hit_t = root;
        record.point = ray.at(root);
        const outward_normal = record.point.sub(self.center).scale(1.0 / self.radius);
        record.setFaceNormal(ray, outward_normal);
        return true;
    }
};
