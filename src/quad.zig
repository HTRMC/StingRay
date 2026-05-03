const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const Interval = @import("interval.zig").Interval;
const Material = @import("material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;

pub const Quad = struct {
    Q: Vec3,
    u: Vec3,
    v: Vec3,
    material: Material,
    bbox: Aabb,
    normal: Vec3,
    D: f32,

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
        };
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

        record.hit_t = t;
        record.point = ray.at(t);
        record.material = self.material;
        record.setFaceNormal(ray, self.normal);
        return true;
    }
};
