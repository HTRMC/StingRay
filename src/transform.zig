const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;

pub const RotateY = struct {
    object: *Hittable,
    sin_theta: f64,
    cos_theta: f64,
    bbox: Aabb,

    pub fn create(allocator: std.mem.Allocator, object: Hittable, angle_degrees: f64) !*RotateY {
        const obj_ptr = try allocator.create(Hittable);
        obj_ptr.* = object;
        const radians = std.math.degreesToRadians(angle_degrees);
        const sin_t = @sin(radians);
        const cos_t = @cos(radians);
        const orig_bbox = obj_ptr.boundingBox();

        var min_pt = Vec3.init(std.math.inf(f64), std.math.inf(f64), std.math.inf(f64));
        var max_pt = Vec3.init(-std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64));

        for (0..2) |i| {
            for (0..2) |j| {
                for (0..2) |k| {
                    const fi: f64 = @floatFromInt(i);
                    const fj: f64 = @floatFromInt(j);
                    const fk: f64 = @floatFromInt(k);
                    const x = fi * orig_bbox.x.max + (1.0 - fi) * orig_bbox.x.min;
                    const y = fj * orig_bbox.y.max + (1.0 - fj) * orig_bbox.y.min;
                    const z = fk * orig_bbox.z.max + (1.0 - fk) * orig_bbox.z.min;

                    const new_x = cos_t * x + sin_t * z;
                    const new_z = -sin_t * x + cos_t * z;

                    min_pt.x = @min(min_pt.x, new_x);
                    min_pt.y = @min(min_pt.y, y);
                    min_pt.z = @min(min_pt.z, new_z);
                    max_pt.x = @max(max_pt.x, new_x);
                    max_pt.y = @max(max_pt.y, y);
                    max_pt.z = @max(max_pt.z, new_z);
                }
            }
        }

        const node = try allocator.create(RotateY);
        node.* = .{
            .object = obj_ptr,
            .sin_theta = sin_t,
            .cos_theta = cos_t,
            .bbox = Aabb.fromPoints(min_pt, max_pt),
        };
        return node;
    }

    pub fn hit(self: *const RotateY, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        const o = ray.origin();
        const d = ray.direction();

        const origin = Vec3.init(
            self.cos_theta * o.x - self.sin_theta * o.z,
            o.y,
            self.sin_theta * o.x + self.cos_theta * o.z,
        );
        const direction = Vec3.init(
            self.cos_theta * d.x - self.sin_theta * d.z,
            d.y,
            self.sin_theta * d.x + self.cos_theta * d.z,
        );
        const rotated = Ray.initTimed(origin, direction, ray.time());

        if (!self.object.hit(rotated, ray_t, record)) return false;

        const p = record.point;
        record.point = Vec3.init(
            self.cos_theta * p.x + self.sin_theta * p.z,
            p.y,
            -self.sin_theta * p.x + self.cos_theta * p.z,
        );
        const n = record.normal;
        record.normal = Vec3.init(
            self.cos_theta * n.x + self.sin_theta * n.z,
            n.y,
            -self.sin_theta * n.x + self.cos_theta * n.z,
        );
        return true;
    }

    pub fn boundingBox(self: *const RotateY) Aabb {
        return self.bbox;
    }
};

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
