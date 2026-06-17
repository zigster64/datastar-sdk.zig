const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const check = b.step("check", "Check if everything compiles (for ZLS)");

    const datastar_module = b.addModule("datastar", .{
        .root_source_file = b.path("src/datastar.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const datastar_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/datastar.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_datastar_tests = b.addRunArtifact(datastar_tests);
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_datastar_tests.step);
    check.dependOn(&datastar_tests.step);

    // Datastar SDK validation harness — builds with plain `zig build`.
    // Listens on :7331 and is exercised by the official Datastar validator:
    //   go run github.com/starfederation/datastar/sdk/tests/cmd/datastar-sdk-tests@latest
    const validation_test = b.addExecutable(.{
        .name = "validation-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/validation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    validation_test.root_module.addImport("datastar", datastar_module);
    b.installArtifact(validation_test);
    check.dependOn(&validation_test.step);

    // Optional example: karlseguin/http.zig port — built only via `zig build http.zig`.
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });
    const httpz_example = b.addExecutable(.{
        .name = "example_1_httpz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/01_basic_httpz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    httpz_example.root_module.addImport("datastar", datastar_module);
    httpz_example.root_module.addImport("httpz", httpz.module("httpz"));

    const httpz_step = b.step("http.zig", "Build the http.zig example to zig-out/bin/example_1_httpz");
    httpz_step.dependOn(&b.addInstallArtifact(httpz_example, .{}).step);
    check.dependOn(&httpz_example.step);

    // Optional example: lalinsky/dusty port — built only via `zig build dusty`.
    const dusty = b.dependency("dusty", .{
        .target = target,
        .optimize = optimize,
    });
    const dusty_example = b.addExecutable(.{
        .name = "example_1_dusty",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/01_basic_dusty.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    dusty_example.root_module.addImport("datastar", datastar_module);
    dusty_example.root_module.addImport("dusty", dusty.module("dusty"));

    const dusty_step = b.step("dusty", "Build the dusty example to zig-out/bin/example_1_dusty");
    dusty_step.dependOn(&b.addInstallArtifact(dusty_example, .{}).step);
    check.dependOn(&dusty_example.step);

    // Kitchen-sink example — stdlib only (no framework), same demo as httpz/dusty ports.
    const stdlib_example = b.addExecutable(.{
        .name = "example_1_stdlib",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/01_basic_stdlib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    stdlib_example.root_module.addImport("datastar", datastar_module);
    const stdlib_install = b.addInstallArtifact(stdlib_example, .{});
    b.getInstallStep().dependOn(&stdlib_install.step);
    const stdlib_step = b.step("stdlib", "Build the stdlib kitchen-sink example to zig-out/bin/example_1_stdlib");
    stdlib_step.dependOn(&stdlib_install.step);
    check.dependOn(&stdlib_example.step);

    // Hello world example — minimal Datastar demo, stdlib only, no framework.
    const hello_world = b.addExecutable(.{
        .name = "hello_world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/hello_world.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hello_world.root_module.addImport("datastar", datastar_module);
    const hello_install = b.addInstallArtifact(hello_world, .{});
    b.getInstallStep().dependOn(&hello_install.step);
    const hello_step = b.step("hello", "Build the hello world example to zig-out/bin/hello_world");
    hello_step.dependOn(&hello_install.step);
    check.dependOn(&hello_world.step);
}
