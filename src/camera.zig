const std = @import("std");
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const Vec3 = color_mod.Vec3;
const write_color = color_mod.write_color;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const HittableList = @import("hittable_list.zig").HittableList;
const Interval = @import("interval.zig").Interval;
const random = @import("random.zig");

pub const Camera = struct {
    aspect_ratio: f32 = 1.0,
    image_width: u32 = 100,
    samples_per_pixel: u32 = 10,
    max_depth: u32 = 10,
    vfov: f32 = 90,
    lookfrom: Vec3 = Vec3.init(0, 0, 0),
    lookat: Vec3 = Vec3.init(0, 0, -1),
    vup: Vec3 = Vec3.init(0, 1, 0),
    defocus_angle: f32 = 0,
    focus_dist: f32 = 10,

    image_height: u32 = undefined,
    pixel_samples_scale: f32 = undefined,
    center: Vec3 = undefined,
    pixel00_loc: Vec3 = undefined,
    pixel_delta_u: Vec3 = undefined,
    pixel_delta_v: Vec3 = undefined,
    basis_u: Vec3 = undefined,
    basis_v: Vec3 = undefined,
    basis_w: Vec3 = undefined,
    defocus_disk_u: Vec3 = undefined,
    defocus_disk_v: Vec3 = undefined,

    pub fn render(self: *Camera, world: HittableList, stdout: anytype, stderr: anytype) !void {
        self.initialize();

        try stdout.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        for (0..self.image_height) |j| {
            try stderr.print("\rScanlines remaining: {} ", .{self.image_height - j});
            for (0..self.image_width) |i| {
                var pixel_color = Color.init(0, 0, 0);
                var sample: u32 = 0;
                while (sample < self.samples_per_pixel) : (sample += 1) {
                    const ray = self.getRay(@intCast(i), @intCast(j));
                    pixel_color = pixel_color.add(self.rayColor(ray, self.max_depth, world));
                }
                try write_color(stdout, pixel_color.scale(self.pixel_samples_scale));
            }
        }

        try stderr.print("\rDone.                 \n", .{});
    }

    fn initialize(self: *Camera) void {
        const image_width_f: f32 = @floatFromInt(self.image_width);
        self.image_height = @max(1, @as(u32, @intFromFloat(image_width_f / self.aspect_ratio)));
        const image_height_f: f32 = @floatFromInt(self.image_height);

        self.pixel_samples_scale = 1.0 / @as(f32, @floatFromInt(self.samples_per_pixel));

        self.center = self.lookfrom;

        const theta = std.math.degreesToRadians(self.vfov);
        const h = @tan(theta / 2.0);
        const viewport_height: f32 = 2.0 * h * self.focus_dist;
        const viewport_width: f32 = viewport_height * (image_width_f / image_height_f);

        self.basis_w = self.lookfrom.sub(self.lookat).normalize();
        self.basis_u = self.vup.cross(self.basis_w).normalize();
        self.basis_v = self.basis_w.cross(self.basis_u);

        const viewport_u = self.basis_u.scale(viewport_width);
        const viewport_v = self.basis_v.scale(-viewport_height);

        self.pixel_delta_u = viewport_u.scale(1.0 / image_width_f);
        self.pixel_delta_v = viewport_v.scale(1.0 / image_height_f);

        const viewport_upper_left = self.center
            .sub(self.basis_w.scale(self.focus_dist))
            .sub(viewport_u.scale(0.5))
            .sub(viewport_v.scale(0.5));
        self.pixel00_loc = viewport_upper_left.add(self.pixel_delta_u.add(self.pixel_delta_v).scale(0.5));

        const defocus_radius = self.focus_dist * @tan(std.math.degreesToRadians(self.defocus_angle / 2.0));
        self.defocus_disk_u = self.basis_u.scale(defocus_radius);
        self.defocus_disk_v = self.basis_v.scale(defocus_radius);
    }

    fn getRay(self: *const Camera, i: u32, j: u32) Ray {
        const offset = sampleSquare();
        const fi: f32 = @floatFromInt(i);
        const fj: f32 = @floatFromInt(j);
        const pixel_sample = self.pixel00_loc
            .add(self.pixel_delta_u.scale(fi + offset.x))
            .add(self.pixel_delta_v.scale(fj + offset.y));
        const ray_origin = if (self.defocus_angle <= 0) self.center else self.defocusDiskSample();
        const ray_direction = pixel_sample.sub(ray_origin);
        return Ray.init(ray_origin, ray_direction);
    }

    fn sampleSquare() Vec3 {
        return Vec3.init(random.float() - 0.5, random.float() - 0.5, 0);
    }

    fn defocusDiskSample(self: *const Camera) Vec3 {
        const p = random.inUnitDisk();
        return self.center.add(self.defocus_disk_u.scale(p.x)).add(self.defocus_disk_v.scale(p.y));
    }

    fn rayColor(self: *const Camera, ray: Ray, depth: u32, world: HittableList) Color {
        if (depth == 0) return Color.init(0, 0, 0);

        var record: HitRecord = undefined;
        if (world.hit(ray, Interval.init(0.001, std.math.inf(f32)), &record)) {
            var scattered: Ray = undefined;
            var attenuation: Color = undefined;
            if (record.material.scatter(ray, record, &attenuation, &scattered)) {
                return color_mod.hadamard(attenuation, self.rayColor(scattered, depth - 1, world));
            }
            return Color.init(0, 0, 0);
        }
        const unit_direction = ray.direction().normalize();
        const blend = 0.5 * (unit_direction.y + 1.0);
        return Color.init(1.0, 1.0, 1.0).scale(1.0 - blend).add(Color.init(0.5, 0.7, 1.0).scale(blend));
    }
};
