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
        var box: Aabb = .{
            .x = if (a.x <= b.x) Interval.init(a.x, b.x) else Interval.init(b.x, a.x),
            .y = if (a.y <= b.y) Interval.init(a.y, b.y) else Interval.init(b.y, a.y),
            .z = if (a.z <= b.z) Interval.init(a.z, b.z) else Interval.init(b.z, a.z),
        };
        box.padToMinimums();
        return box;
    }

    pub fn fromIntervals(x: Interval, y: Interval, z: Interval) Aabb {
        var box: Aabb = .{ .x = x, .y = y, .z = z };
        box.padToMinimums();
        return box;
    }

    pub fn fromBoxes(a: Aabb, b: Aabb) Aabb {
        return .{
            .x = Interval.enclose(a.x, b.x),
            .y = Interval.enclose(a.y, b.y),
            .z = Interval.enclose(a.z, b.z),
        };
    }

    fn padToMinimums(self: *Aabb) void {
        const delta: f32 = 0.0001;
        if (self.x.size() < delta) self.x = self.x.expand(delta);
        if (self.y.size() < delta) self.y = self.y.expand(delta);
        if (self.z.size() < delta) self.z = self.z.expand(delta);
    }

    pub fn axisInterval(self: Aabb, axis: u8) Interval {
        return switch (axis) {
            1 => self.y,
            2 => self.z,
            else => self.x,
        };
    }

    pub fn longestAxis(self: Aabb) u8 {
        const xs = self.x.size();
        const ys = self.y.size();
        const zs = self.z.size();
        if (xs > ys) return if (xs > zs) 0 else 2;
        return if (ys > zs) 1 else 2;
    }

    pub const empty: Aabb = .{ .x = Interval.empty, .y = Interval.empty, .z = Interval.empty };
    pub const universe: Aabb = .{ .x = Interval.universe, .y = Interval.universe, .z = Interval.universe };

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
