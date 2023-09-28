const std = @import("std");

pub fn build(builder: *std.Build) !void {
    // Configs
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    // Define modules
    var module = builder.createModule(.{
        .source_file = .{ .path = "src/main.zig" },
    });
    try builder.modules.put(builder.dupe("zigzag"), module);

    // Add targets
    const library = builder.addStaticLibrary(.{
        .name = "zigzag",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const example_simple_app = builder.addExecutable(.{
        .name = "example-simple-app",
        .root_source_file = .{ .path = "src/examples/simple_app/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const unit_tests = builder.addTest(.{
        .root_source_file = .{ .path = "src/tests/sample_test.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Link dependencies
    example_simple_app.addModule("zigzag", module);
    example_simple_app.linkLibrary(library);

    // Define install paths
    const path = try std.fmt.allocPrint(builder.allocator, "{s}/lib", .{builder.install_prefix});
    defer builder.allocator.free(path);
    library.addLibraryPath(.{ .path = path });

    // Add install steps
    builder.installArtifact(library);
    builder.installArtifact(example_simple_app);

    // Add run steps
    const example_simple_app_run_cmd = builder.addRunArtifact(example_simple_app);
    example_simple_app_run_cmd.step.dependOn(builder.getInstallStep());
    const example_simple_app_run_step = builder.step("run-example-simple-app", "Run example: Simple App");
    example_simple_app_run_step.dependOn(&example_simple_app_run_cmd.step);

    // Add test step
    const run_unit_tests = builder.addRunArtifact(unit_tests);
    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
