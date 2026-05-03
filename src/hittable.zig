const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Sphere = @import("sphere.zig").Sphere;
const Material = @import("material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;
const BvhNode = @import("bvh.zig").BvhNode;

pub const HitRecord = struct {
    point: Vec3,
    normal: Vec3,
    hit_t: f32,
    u: f32 = 0,
    v: f32 = 0,
    front_face: bool,
    material: Material = .none,

    pub fn setFaceNormal(self: *HitRecord, ray: Ray, outward_normal: Vec3) void {
        self.front_face = ray.direction().dot(outward_normal) < 0;
        self.normal = if (self.front_face) outward_normal else outward_normal.scale(-1.0);
    }
};

pub const Hittable = union(enum) {
    sphere: Sphere,
    bvh_node: *BvhNode,

    pub fn hit(self: Hittable, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        return switch (self) {
            inline else => |obj| obj.hit(ray, ray_t, record),
        };
    }

    pub fn boundingBox(self: Hittable) Aabb {
        return switch (self) {
            inline else => |obj| obj.boundingBox(),
        };
    }
};
