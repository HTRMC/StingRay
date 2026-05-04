const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vulkan_sdk = b.graph.environ_map.get("VULKAN_SDK") orelse @panic("VULKAN_SDK not set");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Vulkan SDK
    exe_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "Include" }) });
    exe_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "Lib" }) });
    exe_mod.linkSystemLibrary("vulkan-1", .{});

    // GLFW
    exe_mod.addIncludePath(b.path("vendor/glfw/include"));
    exe_mod.addLibraryPath(b.path("vendor/glfw/lib-mingw-w64"));
    exe_mod.linkSystemLibrary("glfw3dll", .{});

    // Win32
    exe_mod.linkSystemLibrary("gdi32", .{});
    exe_mod.linkSystemLibrary("user32", .{});
    exe_mod.linkSystemLibrary("shell32", .{});

    const exe = b.addExecutable(.{
        .name = "StingRay",
        .root_module = exe_mod,
    });

    // Compile shaders with glslc, install to zig-out/bin/shaders/
    const glslc = b.pathJoin(&.{ vulkan_sdk, "Bin", "glslc.exe" });
    const shader_step = b.step("shaders", "Compile shaders");

    const shaders = [_][]const u8{
        "raytrace.comp",
    };
    for (shaders) |shader_name| {
        const out_name = b.fmt("{s}.spv", .{shader_name});
        const cmd = b.addSystemCommand(&.{glslc});
        cmd.addArg("--target-env=vulkan1.2");
        cmd.addArg("-O");
        cmd.addFileArg(b.path(b.pathJoin(&.{ "src", "shaders", shader_name })));
        cmd.addArg("-o");
        const spv = cmd.addOutputFileArg(out_name);
        const install_spv = b.addInstallFileWithDir(spv, .bin, b.pathJoin(&.{ "shaders", out_name }));
        shader_step.dependOn(&install_spv.step);
        exe.step.dependOn(&install_spv.step);
    }

    b.installArtifact(exe);

    // Copy glfw3.dll next to exe
    const dll_install = b.addInstallBinFile(b.path("vendor/glfw/lib-mingw-w64/glfw3.dll"), "glfw3.dll");
    exe.step.dependOn(&dll_install.step);

    const run_step = b.step("run", "Run StingRay");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
