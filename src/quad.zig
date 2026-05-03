const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const Interval = @import("interval.zig").Interval;
const Material = @import("material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;
const random = @import("random.zig");

pub const Quad = struct {
    Q: Vec3,
    u: Vec3,
    v: Vec3,
    material: Material,
    bbox: Aabb,
    normal: Vec3,
    D: f32,
    w: Vec3,
    area: f32,

    pub fn init(Q: Vec3, u: Vec3, v: Vec3, material: Material) Quad {
        const n = u.cross(v);
        const normal = n.normalize();
        return .{
            .Q = Q,
            .u = u,
            .v = v,
            .material = material,
            .bbox = computeBoundingBox(Q, u, v),
            .normal = normal,
            .D = normal.dot(Q),
            .w = n.scale(1.0 / n.dot(n)),
            .area = n.length(),
        };
    }

    pub fn pdfValue(self: Quad, origin: Vec3, direction: Vec3) f32 {
        var record: HitRecord = undefined;
        if (!self.hit(Ray.init(origin, direction), Interval.init(0.001, std.math.inf(f32)), &record)) return 0;
        const dist_squared = record.hit_t * record.hit_t * direction.dot(direction);
        const cosine = @abs(direction.dot(record.normal) / direction.length());
        return dist_squared / (cosine * self.area);
    }

    pub fn randomToward(self: Quad, origin: Vec3) Vec3 {
        const sample_pt = self.Q.add(self.u.scale(random.float())).add(self.v.scale(random.float()));
        return sample_pt.sub(origin);
    }

    fn computeBoundingBox(Q: Vec3, u: Vec3, v: Vec3) Aabb {
        const diag1 = Aabb.fromPoints(Q, Q.add(u).add(v));
        const diag2 = Aabb.fromPoints(Q.add(u), Q.add(v));
        return Aabb.fromBoxes(diag1, diag2);
    }

    pub fn boundingBox(self: Quad) Aabb {
        return self.bbox;
    }

    pub fn hit(self: Quad, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        const denom = self.normal.dot(ray.direction());
        if (@abs(denom) < 1e-8) return false;

        const t = (self.D - self.normal.dot(ray.origin())) / denom;
        if (!ray_t.contains(t)) return false;

        const intersection = ray.at(t);
        const planar_hitpt = intersection.sub(self.Q);
        const alpha = self.w.dot(planar_hitpt.cross(self.v));
        const beta = self.w.dot(self.u.cross(planar_hitpt));

        if (!isInterior(alpha, beta, record)) return false;

        record.hit_t = t;
        record.point = intersection;
        record.material = self.material;
        record.setFaceNormal(ray, self.normal);
        return true;
    }

    fn isInterior(a: f32, b: f32, record: *HitRecord) bool {
        const unit_int = Interval.init(0, 1);
        if (!unit_int.contains(a) or !unit_int.contains(b)) return false;
        record.u = a;
        record.v = b;
        return true;
    }
};
