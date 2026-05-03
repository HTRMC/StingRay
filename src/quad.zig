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

    pub fn init(Q: Vec3, u: Vec3, v: Vec3, material: Material) Quad {
        return .{
            .Q = Q,
            .u = u,
            .v = v,
            .material = material,
            .bbox = computeBoundingBox(Q, u, v),
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
        _ = self;
        _ = ray;
        _ = ray_t;
        _ = record;
        return false;
    }
};
