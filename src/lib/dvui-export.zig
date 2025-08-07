const Self = @This();

const std = @import("std");
const lib = @import("weatherapp");
const dvui = lib.dvui;

const Backend = dvui.backend;
const Window = dvui.Window;

allocator: std.mem.Allocator,
backend: *Backend,
window: *Window,

/// Runs frames until `dvui.refresh` was not called.
/// Assumes we are just after `dvui.Window.begin`, and on return will be just
/// after a future `dvui.Window.begin`.
pub fn settle(frame: dvui.App.frameFunction) !void {
    for (0..100) |_| {
        const wait_time = try step(frame);

        if (wait_time == 0) {
            // need another frame, someone called refresh()
            continue;
        }

        return;
    }

    return error.unsettled;
}

/// Runs exactly one frame, returning the wait_time from `dvui.Window.end`.
///
/// Assumes we are just after `dvui.Window.begin`, and moves to just after the
/// next `dvui.Window.begin`.
///
/// Useful when you know the frame will not settle, but you need the frame
/// to handle events.
pub fn step(frame: dvui.App.frameFunction) !?u32 {
    const cw = dvui.currentWindow();
    if (try frame() == .close) return error.closed;
    const wait_time = try cw.end(.{});
    try cw.begin(cw.frame_time_ns + 100 * std.time.ns_per_ms);
    return wait_time;
}

pub const InitOptions = struct {
    allocator: std.mem.Allocator = if (@import("builtin").is_test) std.testing.allocator else undefined,
    window_size: dvui.Size = .{ .w = 600, .h = 400 },
};

pub fn init(options: InitOptions) !Self {
    // init SDL backend (creates and owns OS window)
    const backend = try options.allocator.create(Backend);
    errdefer options.allocator.destroy(backend);
    backend.* = switch (Backend.kind) {
        .sdl2, .sdl3 => try Backend.initWindow(.{
            .allocator = options.allocator,
            .size = options.window_size,
            .vsync = false,
            .title = "",
            .hidden = true,
            .fullscreen = true,
        }),
        .testing => Backend.init(.{
            .allocator = options.allocator,
            .size = .cast(options.window_size),
            .size_pixels = options.window_size.scale(2, dvui.Size.Physical),
        }),
        inline else => |kind| {
            std.debug.print("dvui.testing does not support the {s} backend\n", .{@tagName(kind)});
            return error.SkipZigTest;
        },
    };

    const window = try options.allocator.create(Window);
    window.* = try dvui.Window.init(@src(), options.allocator, backend.backend(), .{});

    return .{
        .allocator = options.allocator,
        .backend = backend,
        .window = window,
    };
}

pub fn deinit(self: *Self) void {
    self.window.deinit();
    self.backend.deinit();
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.backend);
}

/// Captures one frame and return the png data for that frame.
/// Captures the physical pixels in rect, or if null the entire OS window.
/// The returned data is allocated by `Self.allocator` and should be freed by the caller.
/// only valid between Window.begin / Window.end
pub fn capturePng(self: *Self, frame: dvui.App.frameFunction, rect: ?dvui.Rect.Physical) ![]const u8 {
    var picture = dvui.Picture.start(rect orelse dvui.windowRectPixels()) orelse {
        std.debug.print("Current backend does not support capturing images\n", .{});
        return error.Unsupported;
    };

    // run the gui code
    if (try frame() == .close) return error.closed;

    // render the retained dialogs and deferred renders
    _ = dvui.currentWindow().endRendering(.{});

    picture.stop();

    // texture will be destroyed in picture.deinit() so grab pixels now
    const png_data = try picture.png(self.allocator);

    // draw texture and destroy
    picture.deinit();

    return png_data;
}
