const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const platform_wasm4_pkg = b.createModule(.{
        .root_source_file = b.path("src/platform_wasm4.zig"),
    });

    const util_pkg = b.createModule(.{
        .root_source_file = b.path("src/util.zig"),
    });

    const bresenham_pkg = b.createModule(.{
        .root_source_file = b.path("src/bresenham.zig"),
    });

    const world_pkg = b.createModule(.{
        .root_source_file = b.path("src/world.zig"),
        .imports = &.{
            .{ .name = "util", .module = util_pkg },
            .{ .name = "bresenham", .module = bresenham_pkg },
        },
    });

    const gfx_pkg = b.createModule(.{
        .root_source_file = b.path("src/gfx.zig"),
        .imports = &.{
            .{ .name = "platform", .module = platform_wasm4_pkg },
            .{ .name = "util", .module = util_pkg },
            .{ .name = "world", .module = world_pkg },
        },
    });

    const sfx_pkg = b.createModule(.{
        .root_source_file = b.path("src/sfx.zig"),
        .imports = &.{.{ .name = "platform", .module = platform_wasm4_pkg }},
    });

    const cart = b.addExecutable(.{
        .name = "cart",
        .root_source_file = b.path("src/main_wasm4.zig"),
        .optimize = optimize,
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
    });
    cart.root_module.export_symbol_names = &[_][]const u8{ "start", "update" };
    cart.entry = .disabled;
    cart.import_memory = true;
    cart.initial_memory = 65536;
    cart.max_memory = 65536;
    cart.stack_size = 14752;
    b.installArtifact(cart);

    cart.root_module.addImport("platform", platform_wasm4_pkg);
    cart.root_module.addImport("gfx", gfx_pkg);
    cart.root_module.addImport("sfx", sfx_pkg);
    cart.root_module.addImport("util", util_pkg);
    cart.root_module.addImport("world", world_pkg);
    cart.root_module.addImport("bresenham", bresenham_pkg);

    cart.root_module.addImport("data", b.createModule(.{
        .root_source_file = b.path("src/data.zig"),
    }));

    const run_native = b.addSystemCommand(&.{ "w4", "run-native" });
    run_native.addArtifactArg(cart);

    const step_run = b.step("run-native", "compile and run the cart");
    step_run.dependOn(&run_native.step);

    { // Release build
        const prefix = b.getInstallPath(.lib, "");
        const cart_opt = b.addSystemCommand(&[_][]const u8{
            "wasm-opt",
            "-Oz",
            "--strip-debug",
            "--strip-producers",
            "--zero-filled-memory",
        });

        cart_opt.addArtifactArg(cart);
        const wasmopt_out = try std.fs.path.join(b.allocator, &.{ prefix, "cart_opt.wasm" });
        defer b.allocator.free(wasmopt_out);
        cart_opt.addArgs(&.{ "--output", wasmopt_out });

        const release_build = b.step("release", "Run wasm-opt on cart.wasm, producing opt.wasm");
        release_build.dependOn(&cart.step);
        release_build.dependOn(&cart_opt.step);
    }
}
