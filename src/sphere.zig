const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const Interval = @import("interval.zig").Interval;
const Material = @import("material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;
const Onb = @import("onb.zig").Onb;
const random = @import("random.zig");

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
        const uv = getSphereUv(outward_normal);
        record.u = uv.u;
        record.v = uv.v;
        record.material = self.material;
        return true;
    }

    fn getSphereUv(p: Vec3) struct { u: f32, v: f32 } {
        const theta = std.math.acos(-p.y);
        const phi = std.math.atan2(-p.z, p.x) + std.math.pi;
        return .{
            .u = phi / (2.0 * std.math.pi),
            .v = theta / std.math.pi,
        };
    }

    pub fn pdfValue(self: Sphere, origin: Vec3, direction: Vec3) f32 {
        var record: HitRecord = undefined;
        if (!self.hit(Ray.init(origin, direction), Interval.init(0.001, std.math.inf(f32)), &record)) return 0;
        const dist_squared = self.center.at(0).sub(origin).dot(self.center.at(0).sub(origin));
        const cos_theta_max = @sqrt(1.0 - self.radius * self.radius / dist_squared);
        const solid_angle = 2.0 * std.math.pi * (1.0 - cos_theta_max);
        return 1.0 / solid_angle;
    }

    pub fn randomToward(self: Sphere, origin: Vec3) Vec3 {
        const direction = self.center.at(0).sub(origin);
        const dist_squared = direction.dot(direction);
        const basis = Onb.init(direction);
        return basis.transform(randomToSphere(self.radius, dist_squared));
    }

    fn randomToSphere(radius: f32, distance_squared: f32) Vec3 {
        const r1 = random.float();
        const r2 = random.float();
        const z = 1.0 + r2 * (@sqrt(1.0 - radius * radius / distance_squared) - 1.0);
        const phi = 2.0 * std.math.pi * r1;
        const sqrt_term = @sqrt(1.0 - z * z);
        const x = @cos(phi) * sqrt_term;
        const y = @sin(phi) * sqrt_term;
        return Vec3.init(x, y, z);
    }
};
