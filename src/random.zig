const std = @import("std");

var prng: std.Random.DefaultPrng = .init(0);

pub fn float() f32 {
    return prng.random().float(f32);
}

pub fn floatRange(min: f32, max: f32) f32 {
    return min + (max - min) * float();
}
