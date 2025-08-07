const std = @import("std");
const assert = std.debug.assert;
const expect = std.debug.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

pub const icons = @import("icons").tvg;
// pub const WavFormWidget = @import("lib/wavformwidget.zig");
pub const GuiContext = @import("lib/guicontext.zig");
pub const db = @import("lib/db.zig");
pub const z2d = @import("osmr").z2d;
pub const OsmrWidget = @import("lib/osmr-widget2.zig");
pub const WeatherWidget = @import("lib/weather-widget.zig");
pub const Tailwind = @import("osmr").Tailwind;
pub const MultiplyWidget = @import("lib/multiply-widget.zig");
pub const Image = @import("image");
pub const dvui = @import("dvui");
pub const datetime = @import("lib/datetime.zig");
pub const weather = @import("weather/src/root.zig");
pub const fifoasync = @import("fifoasync");
pub const wallpaper = @import("wallpaper");

test "all" {
    _ = .{
        // db,
        // datetime,
        // OsmrWidget,
        // MultiplyWidget,
        wallpaper};
    // std.testing.refAllDecls(@This());
}

const builtin = @import("builtin");
const Backend = dvui.backend;

pub const Sched = fifoasync.sched.DefaultSched;
pub const WeatherStyle = WeatherWidget.Style;
