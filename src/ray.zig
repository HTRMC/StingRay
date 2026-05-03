const color = @import("color.zig");
const Vec3 = color.Vec3;

pub const Ray = struct {
    orig: Vec3,
    dir: Vec3,
    tm: f64 = 0,

    pub fn init(origin_: Vec3, direction_: Vec3) Ray {
        return .{ .orig = origin_, .dir = direction_, .tm = 0 };
    }

    pub fn initTimed(origin_: Vec3, direction_: Vec3, time_: f64) Ray {
        return .{ .orig = origin_, .dir = direction_, .tm = time_ };
    }

    pub fn origin(self: Ray) Vec3 {
        return self.orig;
    }

    pub fn direction(self: Ray) Vec3 {
        return self.dir;
    }

    pub fn time(self: Ray) f64 {
        return self.tm;
    }

    pub fn at(self: Ray, t: f64) Vec3 {
        return self.orig.add(self.dir.scale(t));
    }
};
