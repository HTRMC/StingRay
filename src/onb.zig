const std = @import("std");
const Vec3 = @import("color.zig").Vec3;

pub const Onb = struct {
    axis: [3]Vec3,

    pub fn init(n: Vec3) Onb {
        const axis_w = n.normalize();
        const helper = if (@abs(axis_w.x) > 0.9) Vec3.init(0, 1, 0) else Vec3.init(1, 0, 0);
        const axis_v = axis_w.cross(helper).normalize();
        const axis_u = axis_w.cross(axis_v);
        return .{ .axis = .{ axis_u, axis_v, axis_w } };
    }

    pub fn u(self: Onb) Vec3 {
        return self.axis[0];
    }

    pub fn v(self: Onb) Vec3 {
        return self.axis[1];
    }

    pub fn w(self: Onb) Vec3 {
        return self.axis[2];
    }

    pub fn transform(self: Onb, local: Vec3) Vec3 {
        return self.axis[0].scale(local.x)
            .add(self.axis[1].scale(local.y))
            .add(self.axis[2].scale(local.z));
    }
};
