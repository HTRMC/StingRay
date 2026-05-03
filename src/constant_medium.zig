const std = @import("std");
const Vec3 = @import("color.zig").Vec3;
const Color = @import("color.zig").Color;
const Ray = @import("ray.zig").Ray;
const Interval = @import("interval.zig").Interval;
const Aabb = @import("aabb.zig").Aabb;
const hittable_mod = @import("hittable.zig");
const Hittable = hittable_mod.Hittable;
const HitRecord = hittable_mod.HitRecord;
const material_mod = @import("material.zig");
const Material = material_mod.Material;
const Isotropic = material_mod.Isotropic;
const Texture = @import("texture.zig").Texture;
const random = @import("random.zig");

pub const ConstantMedium = struct {
    boundary: *Hittable,
    neg_inv_density: f64,
    phase_function: Material,

    pub fn createFromColor(
        allocator: std.mem.Allocator,
        boundary: Hittable,
        density: f64,
        albedo: Color,
    ) !*ConstantMedium {
        return create(allocator, boundary, density, .{ .isotropic = Isotropic.fromColor(albedo) });
    }

    pub fn create(
        allocator: std.mem.Allocator,
        boundary: Hittable,
        density: f64,
        phase_function: Material,
    ) !*ConstantMedium {
        const obj_ptr = try allocator.create(Hittable);
        obj_ptr.* = boundary;
        const node = try allocator.create(ConstantMedium);
        node.* = .{
            .boundary = obj_ptr,
            .neg_inv_density = -1.0 / density,
            .phase_function = phase_function,
        };
        return node;
    }

    pub fn hit(self: *const ConstantMedium, ray: Ray, ray_t: Interval, record: *HitRecord) bool {
        var rec1: HitRecord = undefined;
        var rec2: HitRecord = undefined;

        if (!self.boundary.hit(ray, Interval.universe, &rec1)) return false;
        if (!self.boundary.hit(ray, Interval.init(rec1.hit_t + 0.0001, std.math.inf(f64)), &rec2)) return false;

        var t1 = rec1.hit_t;
        var t2 = rec2.hit_t;
        if (t1 < ray_t.min) t1 = ray_t.min;
        if (t2 > ray_t.max) t2 = ray_t.max;
        if (t1 >= t2) return false;
        if (t1 < 0) t1 = 0;

        const ray_length = ray.direction().length();
        const distance_inside = (t2 - t1) * ray_length;
        const hit_distance = self.neg_inv_density * @log(random.float());

        if (hit_distance > distance_inside) return false;

        record.hit_t = t1 + hit_distance / ray_length;
        record.point = ray.at(record.hit_t);
        record.normal = Vec3.init(1, 0, 0);
        record.front_face = true;
        record.material = self.phase_function;
        return true;
    }

    pub fn boundingBox(self: *const ConstantMedium) Aabb {
        return self.boundary.boundingBox();
    }
};
