const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;

pub const Translate = struct {
    object: *Hittable,
    offset: Vec3,
    bbox: Aabb,

    pub fn create(allocator: std.mem.Allocator, object: Hittable, offset: Vec3) !*Translate {
        const obj_ptr = try allocator.create(Hittable);
        obj_ptr.* = object;
        const node = try allocator.create(Translate);
        node.* = .{
            .object = obj_ptr,
            .offset = offset,
            .bbox = obj_ptr.boundingBox().offset(offset),
        };
        return node;
    }

    pub fn hit(self: *const Translate, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        const offset_ray = Ray.initTimed(ray.origin().sub(self.offset), ray.direction(), ray.time());
        if (!self.object.hit(offset_ray, ray_t, record)) return false;
        record.point = record.point.add(self.offset);
        return true;
    }

    pub fn boundingBox(self: *const Translate) Aabb {
        return self.bbox;
    }
};
