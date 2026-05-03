const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zlm = b.dependency("zlm", .{
        .target = target,
        .optimize = optimize,
    });

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

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
