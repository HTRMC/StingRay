const std = @import("std");
const Ray = @import("ray.zig").Ray;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;

pub const HittableList = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayList(Hittable),

    pub fn init(allocator: std.mem.Allocator) HittableList {
        return .{ .allocator = allocator, .objects = .empty };
    }

    pub fn deinit(self: *HittableList) void {
        self.objects.deinit(self.allocator);
    }

    pub fn clear(self: *HittableList) void {
        self.objects.clearRetainingCapacity();
    }

    pub fn add(self: *HittableList, object: Hittable) !void {
        try self.objects.append(self.allocator, object);
    }

    pub fn hit(self: HittableList, ray: Ray, ray_tmin: f32, ray_tmax: f32, record: *HitRecord) bool {
        var temp_record: HitRecord = undefined;
        var hit_anything = false;
        var closest_so_far = ray_tmax;

        for (self.objects.items) |object| {
            if (object.hit(ray, ray_tmin, closest_so_far, &temp_record)) {
                hit_anything = true;
                closest_so_far = temp_record.hit_t;
                record.* = temp_record;
            }
        }

        return hit_anything;
    }
};
