const std = @import("std");

pub fn build(b: *std.Build) void {
    const target_query = std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .linux, .cpu_model = .baseline };
    const optimize = b.standardOptimizeOption(.{});

    const main = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(target_query),
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .linkage = .static,
        .name = "2in1",
        .root_module = main,
    });

    const run = b.addRunArtifact(exe);
    const run_step = b.step("run", "run the 2in1");
    run_step.dependOn(&run.step);

    b.installArtifact(exe);
}
