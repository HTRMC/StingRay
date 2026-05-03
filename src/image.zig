const std = @import("std");

const c = @cImport({
    @cInclude("stb_image.h");
});

pub const Image = struct {
    width: i32 = 0,
    height: i32 = 0,
    data: ?[*]u8 = null,

    pub fn load(filename: [*:0]const u8) Image {
        var w: c_int = 0;
        var h: c_int = 0;
        var n: c_int = 0;
        const data = c.stbi_load(filename, &w, &h, &n, 3);
        if (data == null) {
            std.debug.print("ERROR: Could not load image '{s}'\n", .{filename});
            return .{};
        }
        return .{ .width = w, .height = h, .data = @ptrCast(data) };
    }

    pub fn deinit(self: *Image) void {
        if (self.data) |ptr| c.stbi_image_free(ptr);
        self.data = null;
    }

    pub fn pixel(self: Image, x: i32, y: i32) [3]u8 {
        const data = self.data orelse return .{ 255, 0, 255 };
        const cx = std.math.clamp(x, 0, self.width - 1);
        const cy = std.math.clamp(y, 0, self.height - 1);
        const idx: usize = @intCast((cy * self.width + cx) * 3);
        return .{ data[idx], data[idx + 1], data[idx + 2] };
    }
};
