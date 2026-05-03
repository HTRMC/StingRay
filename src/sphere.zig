const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const Interval = @import("interval.zig").Interval;
const Material = @import("material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;

pub const Sphere = struct {
    center: Ray,
    radius: f32,
    material: Material = .none,
    bbox: Aabb,

    pub fn init(static_center: Vec3, radius: f32, material: Material) Sphere {
        const r = @max(0, radius);
        const rvec = Vec3.init(r, r, r);
        return .{
            .center = Ray.init(static_center, Vec3.init(0, 0, 0)),
            .radius = r,
            .material = material,
            .bbox = Aabb.fromPoints(static_center.sub(rvec), static_center.add(rvec)),
        };
    }

    pub fn initMoving(center1: Vec3, center2: Vec3, radius: f32, material: Material) Sphere {
        const r = @max(0, radius);
        const rvec = Vec3.init(r, r, r);
        const center = Ray.init(center1, center2.sub(center1));
        const box1 = Aabb.fromPoints(center.at(0).sub(rvec), center.at(0).add(rvec));
        const box2 = Aabb.fromPoints(center.at(1).sub(rvec), center.at(1).add(rvec));
        return .{
            .center = center,
            .radius = r,
            .material = material,
            .bbox = Aabb.fromBoxes(box1, box2),
        };
    }

    pub fn boundingBox(self: Sphere) Aabb {
        return self.bbox;
    }

    pub fn hit(self: Sphere, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        const current_center = self.center.at(ray.time());
        const origin_to_center = current_center.sub(ray.origin());
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
        const outward_normal = record.point.sub(current_center).scale(1.0 / self.radius);
        record.setFaceNormal(ray, outward_normal);
        record.material = self.material;
        return true;
    }
};
