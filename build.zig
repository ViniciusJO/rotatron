const std = @import("std");

pub fn build(b: *std.Build) void {
    // b.verbose = true;

    const target_query = std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .linux, .cpu_model = .baseline };
    const optimize = b.standardOptimizeOption(.{});

    const clap = b.dependency("clap", .{});

    const main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
        .imports = &[_]std.Build.Module.Import{
            .{ .name = "clap", .module = clap.module("clap") },
        }
    });

    const exe = b.addExecutable(.{
        .linkage = .static,
        .name = "rotatron",
        .root_module = main,
    });

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "runs sr");
    run_step.dependOn(&run.step);

    b.installArtifact(exe);
}
