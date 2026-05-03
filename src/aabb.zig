const Interval = @import("interval.zig").Interval;
const Vec3 = @import("color.zig").Vec3;
const Ray = @import("ray.zig").Ray;

fn axisComponent(v: Vec3, axis: u8) f32 {
    return switch (axis) {
        0 => v.x,
        1 => v.y,
        2 => v.z,
        else => unreachable,
    };
}

pub const Aabb = struct {
    x: Interval = Interval.empty,
    y: Interval = Interval.empty,
    z: Interval = Interval.empty,

    pub fn fromPoints(a: Vec3, b: Vec3) Aabb {
        return .{
            .x = if (a.x <= b.x) Interval.init(a.x, b.x) else Interval.init(b.x, a.x),
            .y = if (a.y <= b.y) Interval.init(a.y, b.y) else Interval.init(b.y, a.y),
            .z = if (a.z <= b.z) Interval.init(a.z, b.z) else Interval.init(b.z, a.z),
        };
    }

    pub fn fromIntervals(x: Interval, y: Interval, z: Interval) Aabb {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn axisInterval(self: Aabb, axis: u8) Interval {
        return switch (axis) {
            1 => self.y,
            2 => self.z,
            else => self.x,
        };
    }

    pub fn hit(self: Aabb, ray: Ray, ray_t_in: Interval) bool {
        var ray_t = ray_t_in;
        var axis: u8 = 0;
        while (axis < 3) : (axis += 1) {
            const ax = self.axisInterval(axis);
            const adinv = 1.0 / axisComponent(ray.direction(), axis);
            const t0 = (ax.min - axisComponent(ray.origin(), axis)) * adinv;
            const t1 = (ax.max - axisComponent(ray.origin(), axis)) * adinv;
            if (t0 < t1) {
                if (t0 > ray_t.min) ray_t.min = t0;
                if (t1 < ray_t.max) ray_t.max = t1;
            } else {
                if (t1 > ray_t.min) ray_t.min = t1;
                if (t0 < ray_t.max) ray_t.max = t0;
            }
            if (ray_t.max <= ray_t.min) return false;
        }
        return true;
    }
};
