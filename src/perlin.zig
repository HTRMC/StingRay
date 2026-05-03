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
        const u = p.x - @floor(p.x);
        const v = p.y - @floor(p.y);
        const w = p.z - @floor(p.z);

        const i: i32 = @intFromFloat(@floor(p.x));
        const j: i32 = @intFromFloat(@floor(p.y));
        const k: i32 = @intFromFloat(@floor(p.z));

        var c: [2][2][2]f32 = undefined;
        for (0..2) |di| {
            for (0..2) |dj| {
                for (0..2) |dk| {
                    const ix = wrapByte(i + @as(i32, @intCast(di)));
                    const iy = wrapByte(j + @as(i32, @intCast(dj)));
                    const iz = wrapByte(k + @as(i32, @intCast(dk)));
                    const idx: usize = @intCast(self.perm_x[ix] ^ self.perm_y[iy] ^ self.perm_z[iz]);
                    c[di][dj][dk] = self.randfloat[idx];
                }
            }
        }
        return trilinearInterp(c, u, v, w);
    }

    fn wrapByte(value: i32) usize {
        const low: u8 = @truncate(@as(u32, @bitCast(value)));
        return low;
    }

    fn trilinearInterp(c: [2][2][2]f32, u: f32, v: f32, w: f32) f32 {
        var accum: f32 = 0.0;
        for (0..2) |i| {
            for (0..2) |j| {
                for (0..2) |k| {
                    const fi: f32 = @floatFromInt(i);
                    const fj: f32 = @floatFromInt(j);
                    const fk: f32 = @floatFromInt(k);
                    accum += (fi * u + (1.0 - fi) * (1.0 - u)) *
                        (fj * v + (1.0 - fj) * (1.0 - v)) *
                        (fk * w + (1.0 - fk) * (1.0 - w)) *
                        c[i][j][k];
                }
            }
        }
        return accum;
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

};
