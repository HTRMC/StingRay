const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlm = b.dependency("zlm", .{
        .target = target,
        .optimize = optimize,
    });

    // -------- CPU renderer (existing) --------
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    exe_mod.addImport("zlm", zlm.module("zlm"));
    exe_mod.addIncludePath(b.path("vendor"));
    exe_mod.addCSourceFile(.{
        .file = b.path("src/stb_impl.c"),
        .flags = &.{},
    });

    const exe = b.addExecutable(.{
        .name = "StingRay",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const asm_step = b.step("asm", "Emit assembly");
    const asm_install = b.addInstallFile(exe.getEmittedAsm(), "StingRay.s");
    asm_step.dependOn(&asm_install.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // -------- GPU renderer (Vulkan compute) --------
    const vulkan_sdk = b.graph.environ_map.get("VULKAN_SDK") orelse {
        std.log.warn("VULKAN_SDK not set, skipping gpu target", .{});
        return;
    };

    const gpu_mod = b.createModule(.{
        .root_source_file = b.path("src/main_gpu.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    gpu_mod.addImport("zlm", zlm.module("zlm"));

    // Vulkan SDK
    gpu_mod.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "Include" }) });
    gpu_mod.addLibraryPath(.{ .cwd_relative = b.pathJoin(&.{ vulkan_sdk, "Lib" }) });
    gpu_mod.linkSystemLibrary("vulkan-1", .{});

    // GLFW
    gpu_mod.addIncludePath(b.path("vendor/glfw/include"));
    gpu_mod.addLibraryPath(b.path("vendor/glfw/lib-mingw-w64"));
    gpu_mod.linkSystemLibrary("glfw3dll", .{});

    // Win32 deps (gdi32 etc may be pulled by glfw)
    gpu_mod.linkSystemLibrary("gdi32", .{});
    gpu_mod.linkSystemLibrary("user32", .{});
    gpu_mod.linkSystemLibrary("shell32", .{});

    const gpu_exe = b.addExecutable(.{
        .name = "StingRayGpu",
        .root_module = gpu_mod,
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
        gpu_exe.step.dependOn(&install_spv.step);
    }

    b.installArtifact(gpu_exe);

    // Copy glfw3.dll next to exe
    const dll_install = b.addInstallBinFile(b.path("vendor/glfw/lib-mingw-w64/glfw3.dll"), "glfw3.dll");
    gpu_exe.step.dependOn(&dll_install.step);

    const run_gpu_step = b.step("run-gpu", "Run the GPU renderer");
    const run_gpu_cmd = b.addRunArtifact(gpu_exe);
    run_gpu_step.dependOn(&run_gpu_cmd.step);
    run_gpu_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_gpu_cmd.addArgs(args);

    const gpu_step = b.step("gpu", "Build the GPU renderer");
    gpu_step.dependOn(&b.addInstallArtifact(gpu_exe, .{}).step);
    gpu_step.dependOn(&dll_install.step);
}
