const std = @import("std");
const random = @import("random.zig");
const Vec3 = @import("color.zig").Vec3;

pub const Perlin = struct {
    pub const point_count: usize = 256;

    randfloat: [point_count]f32,
    perm_x: [point_count]i32,
    perm_y: [point_count]i32,
    perm_z: [point_count]i32,

    pub fn init() Perlin {
        var self: Perlin = undefined;
        for (0..point_count) |i| self.randfloat[i] = random.float();
        generatePerm(&self.perm_x);
        generatePerm(&self.perm_y);
        generatePerm(&self.perm_z);
        return self;
    }

    pub fn noise(self: Perlin, p: Vec3) f32 {
        const i = maskByte(4 * p.x);
        const j = maskByte(4 * p.y);
        const k = maskByte(4 * p.z);
        const idx: usize = @intCast(self.perm_x[i] ^ self.perm_y[j] ^ self.perm_z[k]);
        return self.randfloat[idx];
    }

    fn generatePerm(p: *[point_count]i32) void {
        for (0..point_count) |i| p[i] = @intCast(i);
        permute(p);
    }

    fn permute(p: *[point_count]i32) void {
        var i: i32 = point_count - 1;
        while (i > 0) : (i -= 1) {
            const target = random.intRange(0, i);
            const ui: usize = @intCast(i);
            const ut: usize = @intCast(target);
            const tmp = p[ui];
            p[ui] = p[ut];
            p[ut] = tmp;
        }
    }

    fn maskByte(scaled: f32) usize {
        const as_int: i32 = @intFromFloat(scaled);
        const low: u8 = @truncate(@as(u32, @bitCast(as_int)));
        return low;
    }
};
