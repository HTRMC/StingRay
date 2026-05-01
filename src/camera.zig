const std = @import("std");
const color_mod = @import("color.zig");
const Color = color_mod.Color;
const Vec3 = color_mod.Vec3;
const write_color = color_mod.write_color;
const Ray = @import("ray.zig").Ray;
const HitRecord = @import("hittable.zig").HitRecord;
const HittableList = @import("hittable_list.zig").HittableList;
const Interval = @import("interval.zig").Interval;

pub const Camera = struct {
    aspect_ratio: f32 = 1.0,
    image_width: u32 = 100,

    image_height: u32 = undefined,
    center: Vec3 = undefined,
    pixel00_loc: Vec3 = undefined,
    pixel_delta_u: Vec3 = undefined,
    pixel_delta_v: Vec3 = undefined,

    pub fn render(self: *Camera, world: HittableList, stdout: anytype, stderr: anytype) !void {
        self.initialize();

        try stdout.print("P3\n{} {}\n255\n", .{ self.image_width, self.image_height });

        for (0..self.image_height) |j| {
            try stderr.print("\rScanlines remaining: {} ", .{self.image_height - j});
            const fj: f32 = @floatFromInt(j);
            for (0..self.image_width) |i| {
                const fi: f32 = @floatFromInt(i);
                const pixel_center = self.pixel00_loc
                    .add(self.pixel_delta_u.scale(fi))
                    .add(self.pixel_delta_v.scale(fj));
                const ray_direction = pixel_center.sub(self.center);
                const ray = Ray.init(self.center, ray_direction);

                const pixel_color = self.rayColor(ray, world);
                try write_color(stdout, pixel_color);
            }
        }

        try stderr.print("\rDone.                 \n", .{});
    }

    fn initialize(self: *Camera) void {
        const image_width_f: f32 = @floatFromInt(self.image_width);
        self.image_height = @max(1, @as(u32, @intFromFloat(image_width_f / self.aspect_ratio)));
        const image_height_f: f32 = @floatFromInt(self.image_height);

        self.center = Vec3.init(0, 0, 0);

        const focal_length: f32 = 1.0;
        const viewport_height: f32 = 2.0;
        const viewport_width: f32 = viewport_height * (image_width_f / image_height_f);

        const viewport_u = Vec3.init(viewport_width, 0, 0);
        const viewport_v = Vec3.init(0, -viewport_height, 0);

        self.pixel_delta_u = viewport_u.scale(1.0 / image_width_f);
        self.pixel_delta_v = viewport_v.scale(1.0 / image_height_f);

        const viewport_upper_left = self.center
            .sub(Vec3.init(0, 0, focal_length))
            .sub(viewport_u.scale(0.5))
            .sub(viewport_v.scale(0.5));
        self.pixel00_loc = viewport_upper_left.add(self.pixel_delta_u.add(self.pixel_delta_v).scale(0.5));
    }

    fn rayColor(self: *const Camera, ray: Ray, world: HittableList) Color {
        _ = self;
        var record: HitRecord = undefined;
        if (world.hit(ray, Interval.init(0, std.math.inf(f32)), &record)) {
            return Color.init(record.normal.x + 1, record.normal.y + 1, record.normal.z + 1).scale(0.5);
        }
        const unit_direction = ray.direction().normalize();
        const blend = 0.5 * (unit_direction.y + 1.0);
        return Color.init(1.0, 1.0, 1.0).scale(1.0 - blend).add(Color.init(0.5, 0.7, 1.0).scale(blend));
    }
};
