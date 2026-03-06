const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Dependencies ─────────────────────────────────────────────────
    const websocket_dep = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    // ── Core library modules ────────────────────────────────────────
    const lib_mod = b.addModule("lib", .{
        .root_source_file = b.path("src/lib/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdk_mod = b.addModule("sdk", .{
        .root_source_file = b.path("src/sdk/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lib", .module = lib_mod },
            .{ .name = "websocket", .module = websocket_dep.module("websocket") },
        },
    });

    const regatta_mod = b.addModule("regatta", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "lib", .module = lib_mod },
            .{ .name = "sdk", .module = sdk_mod },
        },
    });

    // ── CLI executable ───────────────────────────────────────────────
    const exe = b.addExecutable(.{
        .name = "regatta",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = if (optimize != .Debug) true else null,
            .unwind_tables = if (optimize != .Debug) .none else null,
            .imports = &.{
                .{ .name = "lib", .module = lib_mod },
                .{ .name = "sdk", .module = sdk_mod },
            },
        }),
    });
    if (optimize != .Debug) {
        exe.link_gc_sections = true;
    }
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run regatta CLI").dependOn(&run.step);

    // ── Tests ────────────────────────────────────────────────────────
    const test_step = b.step("test", "Run all tests");

    // Inline unit tests
    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);

    const sdk_tests = b.addTest(.{ .root_module = sdk_mod });
    test_step.dependOn(&b.addRunArtifact(sdk_tests).step);

    const root_tests = b.addTest(.{ .root_module = regatta_mod });
    test_step.dependOn(&b.addRunArtifact(root_tests).step);

    const cli_test_files = [_][]const u8{
        "src/cli/args.zig",
        "src/cli/output.zig",
        "src/cli/config.zig",
        "src/cli/commands.zig",
        "src/cli/main.zig",
    };
    for (cli_test_files) |test_file| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "lib", .module = lib_mod },
                    .{ .name = "sdk", .module = sdk_mod },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }

    // Dedicated fixture / parity tests
    const test_files = [_][]const u8{
        "tests/signing_parity.zig",
    };
    for (test_files) |test_file| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "lib", .module = lib_mod },
                    .{ .name = "sdk", .module = sdk_mod },
                },
            }),
        });
        test_step.dependOn(&b.addRunArtifact(t).step);
    }
}
