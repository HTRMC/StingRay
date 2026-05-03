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

    pub fn fromList(allocator: std.mem.Allocator, list: HittableList) !*BvhNode {
        return fromSlice(allocator, list.objects.items, 0, list.objects.items.len);
    }

    pub fn fromSlice(
        allocator: std.mem.Allocator,
        objects: []Hittable,
        start: usize,
        end: usize,
    ) !*BvhNode {
        const node = try allocator.create(BvhNode);

        var bbox = Aabb.empty;
        var i: usize = start;
        while (i < end) : (i += 1) {
            bbox = Aabb.fromBoxes(bbox, objects[i].boundingBox());
        }

        const axis: u8 = bbox.longestAxis();
        const span = end - start;

        if (span == 1) {
            const leaf = try allocator.create(Hittable);
            leaf.* = objects[start];
            node.left = leaf;
            node.right = leaf;
        } else if (span == 2) {
            const left_h = try allocator.create(Hittable);
            const right_h = try allocator.create(Hittable);
            left_h.* = objects[start];
            right_h.* = objects[start + 1];
            node.left = left_h;
            node.right = right_h;
        } else {
            std.mem.sort(Hittable, objects[start..end], axis, boxCompare);
            const mid = start + span / 2;
            const left_node = try fromSlice(allocator, objects, start, mid);
            const right_node = try fromSlice(allocator, objects, mid, end);
            const left_h = try allocator.create(Hittable);
            const right_h = try allocator.create(Hittable);
            left_h.* = .{ .bvh_node = left_node };
            right_h.* = .{ .bvh_node = right_node };
            node.left = left_h;
            node.right = right_h;
        }

        node.bbox = bbox;
        return node;
    }

    fn boxCompare(axis: u8, a: Hittable, b: Hittable) bool {
        const a_int = a.boundingBox().axisInterval(axis);
        const b_int = b.boundingBox().axisInterval(axis);
        return a_int.min < b_int.min;
    }

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
