const std = @import("std");
const Ray = @import("ray.zig").Ray;
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const Vec3 = color_mod.Vec3;
const HitRecord = @import("hittable.zig").HitRecord;
const random = @import("random.zig");
const Texture = @import("texture.zig").Texture;

fn refract(uv: Vec3, n: Vec3, etai_over_etat: f32) Vec3 {
    const cos_theta = @min(uv.scale(-1.0).dot(n), 1.0);
    const r_out_perp = uv.add(n.scale(cos_theta)).scale(etai_over_etat);
    const r_out_parallel = n.scale(-@sqrt(@abs(1.0 - r_out_perp.dot(r_out_perp))));
    return r_out_perp.add(r_out_parallel);
}

pub const Lambertian = struct {
    tex: Texture,

    pub fn fromColor(albedo: Color) Lambertian {
        return .{ .tex = Texture.fromColor(albedo) };
    }

    pub fn fromTexture(tex: Texture) Lambertian {
        return .{ .tex = tex };
    }

    pub fn scatter(
        self: Lambertian,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        var direction = record.normal.add(random.unitVector());
        if (color_mod.nearZero(direction)) direction = record.normal;
        scattered.* = Ray.initTimed(record.point, direction, ray_in.time());
        attenuation.* = self.tex.value(record.u, record.v, record.point);
        return true;
    }
};

pub const Metal = struct {
    albedo: Color,
    fuzz: f32,

    pub fn init(albedo: Color, fuzz: f32) Metal {
        return .{ .albedo = albedo, .fuzz = if (fuzz < 1) fuzz else 1 };
    }

    pub fn scatter(
        self: Metal,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        const reflected = ray_in.direction().reflect(record.normal).normalize()
            .add(random.unitVector().scale(self.fuzz));
        scattered.* = Ray.initTimed(record.point, reflected, ray_in.time());
        attenuation.* = self.albedo;
        return reflected.dot(record.normal) > 0;
    }
};

pub const Dielectric = struct {
    refraction_index: f32,

    pub fn scatter(
        self: Dielectric,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        attenuation.* = Color.init(1.0, 1.0, 1.0);
        const ri = if (record.front_face) 1.0 / self.refraction_index else self.refraction_index;
        const unit_direction = ray_in.direction().normalize();
        const cos_theta = @min(unit_direction.scale(-1.0).dot(record.normal), 1.0);
        const sin_theta = @sqrt(1.0 - cos_theta * cos_theta);
        const cannot_refract = ri * sin_theta > 1.0;
        const should_reflect = cannot_refract or reflectance(cos_theta, ri) > random.float();
        const direction = if (should_reflect)
            unit_direction.reflect(record.normal)
        else
            refract(unit_direction, record.normal, ri);
        scattered.* = Ray.initTimed(record.point, direction, ray_in.time());
        return true;
    }

    fn reflectance(cosine: f32, refraction_index: f32) f32 {
        var r0 = (1.0 - refraction_index) / (1.0 + refraction_index);
        r0 = r0 * r0;
        return r0 + (1.0 - r0) * std.math.pow(f32, 1.0 - cosine, 5.0);
    }
};

pub const DiffuseLight = struct {
    tex: Texture,

    pub fn fromColor(emit: Color) DiffuseLight {
        return .{ .tex = Texture.fromColor(emit) };
    }

    pub fn fromTexture(tex: Texture) DiffuseLight {
        return .{ .tex = tex };
    }

    pub fn scatter(
        self: DiffuseLight,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        _ = self;
        _ = ray_in;
        _ = record;
        _ = attenuation;
        _ = scattered;
        return false;
    }

    pub fn emitted(self: DiffuseLight, u: f32, v: f32, p: Vec3) Color {
        return self.tex.value(u, v, p);
    }
};

pub const Isotropic = struct {
    tex: Texture,

    pub fn fromColor(albedo: Color) Isotropic {
        return .{ .tex = Texture.fromColor(albedo) };
    }

    pub fn fromTexture(tex: Texture) Isotropic {
        return .{ .tex = tex };
    }

    pub fn scatter(
        self: Isotropic,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        scattered.* = Ray.initTimed(record.point, random.unitVector(), ray_in.time());
        attenuation.* = self.tex.value(record.u, record.v, record.point);
        return true;
    }
};

pub const Material = union(enum) {
    none: void,
    lambertian: Lambertian,
    metal: Metal,
    dielectric: Dielectric,
    diffuse_light: DiffuseLight,
    isotropic: Isotropic,

    pub fn scatter(
        self: Material,
        ray_in: Ray,
        record: HitRecord,
        attenuation: *Color,
        scattered: *Ray,
    ) bool {
        return switch (self) {
            .none => false,
            inline else => |variant| variant.scatter(ray_in, record, attenuation, scattered),
        };
    }

    pub fn emitted(self: Material, u: f32, v: f32, p: Vec3) Color {
        return switch (self) {
            .diffuse_light => |light| light.emitted(u, v, p),
            else => Color.init(0, 0, 0),
        };
    }
};
