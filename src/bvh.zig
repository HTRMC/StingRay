const std = @import("std");
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;
const HittableList = @import("hittable_list.zig").HittableList;

pub const BvhNode = struct {
    left: *Hittable,
    right: *Hittable,
    bbox: Aabb,

    pub fn hit(self: *const BvhNode, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        if (!self.bbox.hit(ray, ray_t)) return false;

        const hit_left = self.left.hit(ray, ray_t, record);
        const right_max = if (hit_left) record.hit_t else ray_t.max;
        const hit_right = self.right.hit(ray, Interval.init(ray_t.min, right_max), record);

        return hit_left or hit_right;
    }

    pub fn boundingBox(self: *const BvhNode) Aabb {
        return self.bbox;
    }
};
