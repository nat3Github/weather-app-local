const std = @import("std");
const update = @import("update.zig");
const GitDependency = update.GitDependency;
fn update_step(step: *std.Build.Step, _: std.Build.Step.MakeOptions) !void {
    const deps = &.{
        GitDependency{
            // image
            .url = "https://github.com/nat3Github/zig-lib-image",
            .branch = "main",
        },
        // GitDependency{
        //     // z2d
        //     .url = "https://github.com/nat3Github/zig-lib-z2d-dev-fork",
        //     .branch = "main",
        // },
        GitDependency{
            // tailwind
            .url = "https://github.com/nat3Github/zig-lib-tailwind-colors",
            .branch = "master",
        },
        GitDependency{
            // fifoasync
            .url = "https://github.com/nat3Github/zig-lib-fifoasync",
            .branch = "master",
        },
        GitDependency{
            // sqlite
            .url = "https://github.com/nat3Github/zig-lib-sqlite3",
            .branch = "master",
        },
        GitDependency{
            // osmr
            .url = "https://github.com/nat3Github/zig-lib-osmr",
            .branch = "master",
        },
        GitDependency{
            // icons
            .url = "https://github.com/nat3Github/zig-lib-icons",
            .branch = "main",
        },
        GitDependency{
            // serde
            .url = "https://github.com/nat3Github/zig-lib-serialization-dev-fork",
            .branch = "master",
        },
        GitDependency{
            //dvui
            .url = "https://github.com/nat3Github/zig-lib-dvui-dev-fork",
            .branch = "weatherapp",
        },
    };
    try update.update_dependency(step.owner.allocator, deps);
}

pub fn build(b: *std.Build) void {
    const step = b.step("update", "update git dependencies");
    step.makeFn = update_step;
    // if (true) return;

    const step_run = b.step("run", "Run the app");
    const step_test = b.step("test", "test app");
    // const step_run_og = b.step("run-og", "Run the app");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const weatherapp_mod = b.addModule("weatherapp", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    const wallpaper_transc = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .use_clang = true,
        .root_source_file = b.path("src/lib/apple/wallpaper.h"),
    });
    const wallpaper_mod = wallpaper_transc.createModule();
    wallpaper_mod.addCSourceFile(.{
        .file = b.path("src/lib/apple//wallpaper.m"),
        .language = .objective_c,
    });
    if (target.result.os.tag == .macos) {
        weatherapp_mod.addImport("wallpaper", wallpaper_mod);
    }

    const icons_module = b.dependency("icons", .{
        .target = target,
        .optimize = optimize,
    }).module("icons");
    weatherapp_mod.addImport("icons", icons_module);

    const serialization_mod = b.dependency("serialization", .{
        .target = target,
        .optimize = optimize,
    }).module("serialization");
    weatherapp_mod.addImport("serde", serialization_mod);

    const sqlite3_dep = b.dependency("sqlite3", .{
        .target = target,
        .optimize = optimize,
    });
    const sqlite3_mod = sqlite3_dep.module("sqlite3");
    weatherapp_mod.addImport("sqlite", sqlite3_mod);

    const fifoasync_dep = b.dependency("fifoasync", .{
        .target = target,
        .optimize = optimize,
    });
    const fifoasync_mod = fifoasync_dep.module("fifoasync");
    weatherapp_mod.addImport("fifoasync", fifoasync_mod);

    const osmr_dep = b.dependency("osmr", .{
        .target = target,
        .optimize = optimize,
    });
    const osmr_mod = osmr_dep.module("osmr");
    weatherapp_mod.addImport("osmr", osmr_mod);

    const dvui_dep = b.dependency("dvui", .{
        .target = target,
        .optimize = optimize,
    });
    const dvui_sdl_mod = dvui_dep.module("dvui_sdl3");
    weatherapp_mod.addImport("dvui", dvui_sdl_mod);

    const image_module = b.dependency("image", .{
        .target = target,
        .optimize = optimize,
    }).module("image");
    weatherapp_mod.addImport("image", image_module);

    const tailwind_module = b.dependency("tailwind", .{
        .target = target,
        .optimize = optimize,
    }).module("tailwind");
    weatherapp_mod.addImport("tailwind", tailwind_module);

    const test1 = b.addTest(.{
        .root_module = weatherapp_mod,
    });
    b.installArtifact(test1);
    const test1_run = b.addRunArtifact(test1);
    step_test.dependOn(&test1_run.step);

    const app = b.addExecutable(.{
        .name = "app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    app.root_module.addImport("weatherapp", weatherapp_mod);

    b.installArtifact(app);

    const run_cmd1 = b.addRunArtifact(app);
    run_cmd1.step.dependOn(b.getInstallStep());
    step_run.dependOn(&run_cmd1.step);
}

test "test all refs" {
    std.testing.refAllDeclsRecursive(@This());
}
