const std = @import("std");

pub const Interval = struct {
    min: f32,
    max: f32,

    pub const empty: Interval = .{ .min = std.math.inf(f32), .max = -std.math.inf(f32) };
    pub const universe: Interval = .{ .min = -std.math.inf(f32), .max = std.math.inf(f32) };

    pub fn init(min: f32, max: f32) Interval {
        return .{ .min = min, .max = max };
    }

    pub fn enclose(a: Interval, b: Interval) Interval {
        return .{
            .min = if (a.min <= b.min) a.min else b.min,
            .max = if (a.max >= b.max) a.max else b.max,
        };
    }

    pub fn size(self: Interval) f32 {
        return self.max - self.min;
    }

    pub fn contains(self: Interval, x: f32) bool {
        return self.min <= x and x <= self.max;
    }

    pub fn surrounds(self: Interval, x: f32) bool {
        return self.min < x and x < self.max;
    }

    pub fn clamp(self: Interval, x: f32) f32 {
        if (x < self.min) return self.min;
        if (x > self.max) return self.max;
        return x;
    }

    pub fn expand(self: Interval, delta: f32) Interval {
        const padding = delta / 2.0;
        return .{ .min = self.min - padding, .max = self.max + padding };
    }
};
