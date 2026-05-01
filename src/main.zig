const std = @import("std");
const Color = @import("color.zig").Color;
const Vec3 = @import("color.zig").Vec3;
const write_color = @import("color.zig").write_color;
const Ray = @import("ray.zig").Ray;

fn hit_sphere(center: Vec3, radius: f32, ray: Ray) f32 {
    const origin_to_center = center.sub(ray.origin());
    const quadratic_a = ray.direction().dot(ray.direction());
    const half_b = ray.direction().dot(origin_to_center);
    const quadratic_c = origin_to_center.dot(origin_to_center) - radius * radius;
    const discriminant = half_b * half_b - quadratic_a * quadratic_c;
    if (discriminant < 0) {
        return -1.0;
    } else {
        return (half_b - @sqrt(discriminant)) / quadratic_a;
    }
}

fn ray_color(ray: Ray) Color {
    const hit_t = hit_sphere(Vec3.init(0, 0, -1), 0.5, ray);
    if (hit_t > 0.0) {
        const normal = ray.at(hit_t).sub(Vec3.init(0, 0, -1)).normalize();
        return Color.init(normal.x + 1, normal.y + 1, normal.z + 1).scale(0.5);
    }

    const unit_direction = ray.direction().normalize();
    const blend = 0.5 * (unit_direction.y + 1.0);
    return Color.init(1.0, 1.0, 1.0).scale(1.0 - blend).add(Color.init(0.5, 0.7, 1.0).scale(blend));
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_writer.interface;
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    const stderr = &stderr_writer.interface;

    const aspect_ratio: f32 = 16.0 / 9.0;
    const image_width: u32 = 400;
    const image_width_f: f32 = @floatFromInt(image_width);
    const image_height: u32 = @max(1, @as(u32, @intFromFloat(image_width_f / aspect_ratio)));
    const image_height_f: f32 = @floatFromInt(image_height);

    const focal_length: f32 = 1.0;
    const viewport_height: f32 = 2.0;
    const viewport_width: f32 = viewport_height * (image_width_f / image_height_f);
    const camera_center = Vec3.init(0, 0, 0);

    const viewport_u = Vec3.init(viewport_width, 0, 0);
    const viewport_v = Vec3.init(0, -viewport_height, 0);

    const pixel_delta_u = viewport_u.scale(1.0 / image_width_f);
    const pixel_delta_v = viewport_v.scale(1.0 / image_height_f);

    const viewport_upper_left = camera_center
        .sub(Vec3.init(0, 0, focal_length))
        .sub(viewport_u.scale(0.5))
        .sub(viewport_v.scale(0.5));
    const pixel00_loc = viewport_upper_left.add(pixel_delta_u.add(pixel_delta_v).scale(0.5));

    try stdout.print("P3\n{} {}\n255\n", .{ image_width, image_height });

    for (0..image_height) |j| {
        const fj: f32 = @floatFromInt(j);
        for (0..image_width) |i| {
            const fi: f32 = @floatFromInt(i);
            const pixel_center = pixel00_loc
                .add(pixel_delta_u.scale(fi))
                .add(pixel_delta_v.scale(fj));
            const ray_direction = pixel_center.sub(camera_center);
            const r = Ray.init(camera_center, ray_direction);

            const pixel_color = ray_color(r);
            try write_color(stdout, pixel_color);
        }
    }

    try stderr.print("\rDone.                 \n", .{});
}
