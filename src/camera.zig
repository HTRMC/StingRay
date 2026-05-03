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
const Hittable = @import("hittable.zig").Hittable;
const ScatterRecord = @import("material.zig").ScatterRecord;
const pdf_mod = @import("pdf.zig");
const Pdf = pdf_mod.Pdf;
const CosinePdf = pdf_mod.CosinePdf;
const HittablePdf = pdf_mod.HittablePdf;

pub const Camera = struct {
    aspect_ratio: f64 = 1.0,
    image_width: u32 = 100,
    samples_per_pixel: u32 = 10,
    max_depth: u32 = 10,
    vfov: f64 = 90,
    lookfrom: Vec3 = Vec3.init(0, 0, 0),
    lookat: Vec3 = Vec3.init(0, 0, -1),
    vup: Vec3 = Vec3.init(0, 1, 0),
    defocus_angle: f64 = 0,
    focus_dist: f64 = 10,
    background: Color = Color.init(0, 0, 0),

    image_height: u32 = undefined,
    sqrt_spp: u32 = undefined,
    recip_sqrt_spp: f64 = undefined,
    pixel_samples_scale: f64 = undefined,
    center: Vec3 = undefined,
    pixel00_loc: Vec3 = undefined,
    pixel_delta_u: Vec3 = undefined,
    pixel_delta_v: Vec3 = undefined,
    basis_u: Vec3 = undefined,
    basis_v: Vec3 = undefined,
    basis_w: Vec3 = undefined,
    defocus_disk_u: Vec3 = undefined,
    defocus_disk_v: Vec3 = undefined,

    pub fn render(self: *Camera, world: HittableList, lights: ?*const Hittable, stdout: anytype, stderr: anytype) !void {
        self.initialize();

        try stdout.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        for (0..self.image_height) |j| {
            try stderr.print("\rScanlines remaining: {} ", .{self.image_height - j});
            for (0..self.image_width) |i| {
                var pixel_color = Color.init(0, 0, 0);
                var s_j: u32 = 0;
                while (s_j < self.sqrt_spp) : (s_j += 1) {
                    var s_i: u32 = 0;
                    while (s_i < self.sqrt_spp) : (s_i += 1) {
                        const ray = self.getRay(@intCast(i), @intCast(j), s_i, s_j);
                        const sample = self.rayColor(ray, self.max_depth, world, lights);
                        const sx = if (sample.x != sample.x) 0 else sample.x;
                        const sy = if (sample.y != sample.y) 0 else sample.y;
                        const sz = if (sample.z != sample.z) 0 else sample.z;
                        pixel_color = pixel_color.add(Color.init(sx, sy, sz));
                    }
                }
                try write_color(stdout, pixel_color.scale(self.pixel_samples_scale));
            }
        }

        try stderr.print("\rDone.                 \n", .{});
    }

    fn initialize(self: *Camera) void {
        const image_width_f: f64 = @floatFromInt(self.image_width);
        self.image_height = @max(1, @as(u32, @intFromFloat(image_width_f / self.aspect_ratio)));
        const image_height_f: f64 = @floatFromInt(self.image_height);

        const sqrt_spp_f = @sqrt(@as(f64, @floatFromInt(self.samples_per_pixel)));
        self.sqrt_spp = @max(1, @as(u32, @intFromFloat(sqrt_spp_f)));
        const sqrt_spp_actual: f64 = @floatFromInt(self.sqrt_spp);
        self.pixel_samples_scale = 1.0 / (sqrt_spp_actual * sqrt_spp_actual);
        self.recip_sqrt_spp = 1.0 / sqrt_spp_actual;

        self.center = self.lookfrom;

        const theta = std.math.degreesToRadians(self.vfov);
        const h = @tan(theta / 2.0);
        const viewport_height: f64 = 2.0 * h * self.focus_dist;
        const viewport_width: f64 = viewport_height * (image_width_f / image_height_f);

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

    fn getRay(self: *const Camera, i: u32, j: u32, s_i: u32, s_j: u32) Ray {
        const offset = self.sampleSquareStratified(s_i, s_j);
        const fi: f64 = @floatFromInt(i);
        const fj: f64 = @floatFromInt(j);
        const pixel_sample = self.pixel00_loc
            .add(self.pixel_delta_u.scale(fi + offset.x))
            .add(self.pixel_delta_v.scale(fj + offset.y));
        const ray_origin = if (self.defocus_angle <= 0) self.center else self.defocusDiskSample();
        const ray_direction = pixel_sample.sub(ray_origin);
        const ray_time = random.float();
        return Ray.initTimed(ray_origin, ray_direction, ray_time);
    }

    fn sampleSquareStratified(self: *const Camera, s_i: u32, s_j: u32) Vec3 {
        const fs_i: f64 = @floatFromInt(s_i);
        const fs_j: f64 = @floatFromInt(s_j);
        const px = ((fs_i + random.float()) * self.recip_sqrt_spp) - 0.5;
        const py = ((fs_j + random.float()) * self.recip_sqrt_spp) - 0.5;
        return Vec3.init(px, py, 0);
    }

    fn defocusDiskSample(self: *const Camera) Vec3 {
        const p = random.inUnitDisk();
        return self.center.add(self.defocus_disk_u.scale(p.x)).add(self.defocus_disk_v.scale(p.y));
    }

    fn rayColor(self: *const Camera, ray: Ray, depth: u32, world: HittableList, lights: ?*const Hittable) Color {
        if (depth == 0) return Color.init(0, 0, 0);

        var record: HitRecord = undefined;
        if (!world.hit(ray, Interval.init(0.001, std.math.inf(f64)), &record)) {
            return self.background;
        }

        var srec: ScatterRecord = .{};
        const color_from_emission = record.material.emitted(record, record.u, record.v, record.point);

        if (!record.material.scatter(ray, record, &srec)) {
            return color_from_emission;
        }

        if (srec.skip_pdf) {
            return color_mod.hadamard(srec.attenuation, self.rayColor(srec.skip_pdf_ray, depth - 1, world, lights));
        }

        const cosine_pdf = srec.pdf;
        var pdf_value: f64 = 0;
        var direction: Vec3 = undefined;
        if (lights) |light_obj| {
            const light_pdf: Pdf = .{ .hittable = HittablePdf.init(light_obj, record.point) };
            direction = if (random.float() < 0.5) light_pdf.generate() else cosine_pdf.generate();
            pdf_value = 0.5 * light_pdf.value(direction) + 0.5 * cosine_pdf.value(direction);
        } else {
            direction = cosine_pdf.generate();
            pdf_value = cosine_pdf.value(direction);
        }

        const scattered = Ray.initTimed(record.point, direction, ray.time());
        const scattering_pdf = record.material.scatteringPdf(ray, record, scattered);
        const incoming = self.rayColor(scattered, depth - 1, world, lights);
        const color_from_scatter = color_mod.hadamard(srec.attenuation, incoming).scale(scattering_pdf / pdf_value);
        return color_from_emission.add(color_from_scatter);
    }
};
