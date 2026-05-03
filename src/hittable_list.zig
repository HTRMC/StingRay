const std = @import("std");
const Ray = @import("ray.zig").Ray;
const Vec3 = @import("color.zig").Vec3;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;
const random = @import("random.zig");

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

    pub fn pdfValue(self: HittableList, origin: Vec3, direction: Vec3) f32 {
        const count = self.objects.items.len;
        if (count == 0) return 0;
        const weight = 1.0 / @as(f32, @floatFromInt(count));
        var sum: f32 = 0;
        for (self.objects.items) |object| {
            sum += weight * object.pdfValue(origin, direction);
        }
        return sum;
    }

    pub fn randomToward(self: HittableList, origin: Vec3) Vec3 {
        const count = self.objects.items.len;
        if (count == 0) return Vec3.init(1, 0, 0);
        const idx: usize = @intCast(random.intRange(0, @intCast(count - 1)));
        return self.objects.items[idx].randomToward(origin);
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
