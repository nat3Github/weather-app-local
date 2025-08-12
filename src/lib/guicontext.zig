const std = @import("std");
const builtin = @import("builtin");
const dvui = @import("dvui");
const Backend = dvui.backend;
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const fifoasync = @import("fifoasync");

pub const Sched = fifoasync.sched.DefaultSched;
pub const AsyncExecutor = fifoasync.sched.AsyncExecutor;

// const MapsWidget = root.OsmrWidget.OsmrWidgetFlex(Sched.AsyncExecutor);
// const WeatherWidget = root.WeatherWidget.WeatherWidget(Sched.AsyncExecutor);

pub const Location = struct {
    zip: u32,
    lat: f32,
    lon: f32,
    offset: i64,
};

const MultiplyWidget = root.MultiplyWidget;
pub const WeatherStyle = root.WeatherWidget.Style;

pub const MAX_WEATHER_POINTS: usize = root.db.WEATHER_DATAPOINTS;
const GuiContext = @This();
const Menu = enum {
    const This = @This();
    const menu_str = @typeInfo(This).@"enum".fields;
    fn f_str() []const []const u8 {
        var s: [menu_str.len][]const u8 = undefined;
        inline for (&s, 0..) |*x, i| {
            x.* = menu_str[i].name;
        }
        return &s;
    }
    Menu,
    Browse,
    Settings,
};

vsync: bool = true,
show_demo: bool = true,
scale_val: f32 = 1.2,
show_dialog_outside_frame: bool = false,
backend: ?Backend = null,
win: ?*dvui.Window = null,
zoom: u32 = 9,
error_timer: ?std.time.Timer = null,
gp_timer: ?std.time.Timer = null,
inactivity_timer: std.time.Timer,
retry_sec: u64 = 0,
quit: bool = false,

menu: Menu = .Menu,
// maps_widget_basic: MapsWidget,
// maps_widget_lines: MapsWidget,
// weather_widget: WeatherWidget,
multi_widget: MultiplyWidget,
sched: Sched,
style: WeatherStyle = .None,
blendmode: usize = 0,
datapoint: usize = 0,

location: ?Location = null,

pool: *std.Thread.Pool,
alloc: Allocator,

pub fn get_location(ctx: *GuiContext) !Location {
    var tarena = std.heap.ArenaAllocator.init(ctx.alloc);
    defer tarena.deinit();
    const times = 5;
    for (0..times) |i| {
        const loc = root.weather.util.geo_location_leaky(tarena.allocator()) catch |e| {
            if (i + 1 == times) {
                return e;
            } else continue;
        };
        const rloc = Location{
            .lat = loc.lat,
            .lon = loc.lon,
            .offset = loc.offset,
            .zip = loc.zip,
        };
        return rloc;
    }
    unreachable;
}

pub fn init(alloc: Allocator) !GuiContext {
    var sched = try Sched.init(alloc, .{
        .N_queue_capacity = 1024,
        .N_threads = 2,
    });
    errdefer sched.deinit(alloc);
    const thread_count = 16;
    const pool: *std.Thread.Pool = try alloc.create(std.Thread.Pool);
    try std.Thread.Pool.init(pool, .{ .allocator = alloc, .n_jobs = thread_count });
    errdefer pool.deinit();
    const multi = try MultiplyWidget.init(alloc);
    errdefer multi.deinit(alloc);
    return GuiContext{
        .alloc = alloc,
        .multi_widget = multi,
        .sched = sched,
        .pool = pool,
        .inactivity_timer = std.time.Timer.start() catch panic("timer creation failed", .{}),
    };
}
pub fn deinit(self: *GuiContext) void {
    const alloc = self.alloc;
    self.multi_widget.deinit(alloc);
    std.debug.print("multi deinit\n", .{});
    self.sched.deinit(alloc);
    std.debug.print("sched deinit\n", .{});
    self.pool.deinit();
    alloc.destroy(self.pool);
}
pub fn inactive(self: *GuiContext) bool {
    return self.inactivity_timer.read() > 10 * 1_000_000_000;
}

pub fn update_location(self: *GuiContext) !void {
    if (self.location == null) {
        self.location = try self.get_location();
    }
}

pub fn check_if_should_export(ctx: *GuiContext, export_ctx: *GuiContext) bool {
    if (ctx.location) |ml| {
        if (ctx.multi_widget.weather_widget.center_info.data) |d| {
            const now_idx = root.WeatherWidget.get_now_idx(d);
            if (export_ctx.datapoint != now_idx or
                export_ctx.style != ctx.style or
                export_ctx.zoom != ctx.zoom)
            {
                export_ctx.location = ml;
                export_ctx.datapoint = now_idx;
                export_ctx.zoom = ctx.zoom;
                export_ctx.style = ctx.style;
                return true;
            }
        }
    }
    return false;
}
