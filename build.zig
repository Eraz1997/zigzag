const std = @import("std");

pub fn build(builder: *std.Build) !void {
    // - Configs - //
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    // - Modules - //
    const module = builder.createModule(.{
        .source_file = .{ .path = "src/main.zig" },
    });
    try builder.modules.put(builder.dupe("zigzag"), module);

    // - Library - //

    // Add target
    const library = builder.addStaticLibrary(.{
        .name = "zigzag",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Define install paths
    const path = try std.fmt.allocPrint(builder.allocator, "{s}/lib", .{builder.install_prefix});
    defer builder.allocator.free(path);
    library.addLibraryPath(.{ .path = path });

    // Add install step
    builder.installArtifact(library);

    // - Unit tests - //

    // Add target
    const unit_tests = builder.addTest(.{
        .root_source_file = .{ .path = "src/tests/sample_test.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add run tests step
    const run_unit_tests = builder.addRunArtifact(unit_tests);
    const test_step = builder.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // - Examples - //

    // Add targets
    const example_empty_app = builder.addExecutable(.{
        .name = "example-empty-app",
        .root_source_file = .{ .path = "src/examples/empty_app/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const example_app_with_routers_and_error_handlers = builder.addExecutable(.{
        .name = "example-app-with-routers-and-error-handlers",
        .root_source_file = .{ .path = "src/examples/app_with_routers_and_error_handlers/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add modules
    example_empty_app.addModule("zigzag", module);
    example_app_with_routers_and_error_handlers.addModule("zigzag", module);

    // Link dependencies
    example_empty_app.linkLibrary(library);
    example_app_with_routers_and_error_handlers.linkLibrary(library);

    // Add install steps
    builder.installArtifact(example_empty_app);
    builder.installArtifact(example_app_with_routers_and_error_handlers);

    // Add run steps
    const example_empty_app_run_cmd = builder.addRunArtifact(example_empty_app);
    example_empty_app_run_cmd.step.dependOn(builder.getInstallStep());
    const example_empty_app_run_step = builder.step("run-example-empty-app", "Run example: empty app");
    example_empty_app_run_step.dependOn(&example_empty_app_run_cmd.step);

    const example_app_with_routers_and_error_handlers_run_cmd = builder.addRunArtifact(example_app_with_routers_and_error_handlers);
    example_app_with_routers_and_error_handlers_run_cmd.step.dependOn(builder.getInstallStep());
    const example_app_with_routers_and_error_handlers_run_step = builder.step("run-example-app-with-routers-and-error-handlers", "Run example: app with routers and error handlers");
    example_app_with_routers_and_error_handlers_run_step.dependOn(&example_app_with_routers_and_error_handlers_run_cmd.step);
}
