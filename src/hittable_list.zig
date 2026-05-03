const std = @import("std");
const Ray = @import("ray.zig").Ray;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;

pub const HittableList = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayList(Hittable),
    bbox: Aabb = .{},

    pub fn init(allocator: std.mem.Allocator) HittableList {
        return .{ .allocator = allocator, .objects = .empty };
    }

    pub fn deinit(self: *HittableList) void {
        self.objects.deinit(self.allocator);
    }

    pub fn clear(self: *HittableList) void {
        self.objects.clearRetainingCapacity();
        self.bbox = .{};
    }

    pub fn add(self: *HittableList, object: Hittable) !void {
        try self.objects.append(self.allocator, object);
        self.bbox = Aabb.fromBoxes(self.bbox, object.boundingBox());
    }

    pub fn boundingBox(self: HittableList) Aabb {
        return self.bbox;
    }

    pub fn hit(self: HittableList, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        var temp_record: HitRecord = undefined;
        var hit_anything = false;
        var closest_so_far = ray_t.max;

        for (self.objects.items) |object| {
            if (object.hit(ray, Interval.init(ray_t.min, closest_so_far), &temp_record)) {
                hit_anything = true;
                closest_so_far = temp_record.hit_t;
                record.* = temp_record;
            }
        }

        return hit_anything;
    }
};
