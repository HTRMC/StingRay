const std = @import("std");
const Vec3 = @import("color.zig").Vec3;

var prng: std.Random.DefaultPrng = .init(0);

pub fn float() f64 {
    return prng.random().float(f64);
}

pub fn intRange(min: i32, max: i32) i32 {
    return prng.random().intRangeAtMost(i32, min, max);
}

pub fn floatRange(min: f64, max: f64) f64 {
    return min + (max - min) * float();
}

pub fn vec() Vec3 {
    return Vec3.init(float(), float(), float());
}

pub fn vecRange(min: f64, max: f64) Vec3 {
    return Vec3.init(floatRange(min, max), floatRange(min, max), floatRange(min, max));
}

pub fn unitVector() Vec3 {
    while (true) {
        const candidate = vecRange(-1, 1);
        const len_sq = candidate.dot(candidate);
        if (1e-30 < len_sq and len_sq <= 1) {
            return candidate.scale(1.0 / @sqrt(len_sq));
        }
    }
}

pub fn onHemisphere(normal: Vec3) Vec3 {
    const on_unit_sphere = unitVector();
    if (on_unit_sphere.dot(normal) > 0.0) return on_unit_sphere;
    return on_unit_sphere.scale(-1.0);
}

pub fn inUnitDisk() Vec3 {
    while (true) {
        const candidate = Vec3.init(floatRange(-1, 1), floatRange(-1, 1), 0);
        if (candidate.dot(candidate) < 1) return candidate;
    }
}

pub fn cosineDirection() Vec3 {
    const r1 = float();
    const r2 = float();
    const phi = 2.0 * std.math.pi * r1;
    const sqrt_r2 = @sqrt(r2);
    const x = @cos(phi) * sqrt_r2;
    const y = @sin(phi) * sqrt_r2;
    const z = @sqrt(1.0 - r2);
    return Vec3.init(x, y, z);
}
