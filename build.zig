const std = @import("std");

pub fn build(b: *std.Build) void {
    // Configs
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add targets
    const example_simple_app = b.addExecutable(.{
        .name = "example-simple-app",
        .root_source_file = .{ .path = "src/examples/simple_app/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests/sample_test.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add install steps
    b.installArtifact(example_simple_app);

    // Add run steps
    const example_simple_app_run_cmd = b.addRunArtifact(example_simple_app);
    example_simple_app_run_cmd.step.dependOn(b.getInstallStep());
    const example_simple_app_run_step = b.step("run-example-simple-app", "Run example: Simple App");
    example_simple_app_run_step.dependOn(&example_simple_app_run_cmd.step);

    // Add test step
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
