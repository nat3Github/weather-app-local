const std = @import("std");
const builtin = @import("builtin");
const lib = @import("weatherapp");
const dvui = lib.dvui;
const Backend = dvui.backend;
const assert = std.debug.assert;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const GuiContext = lib.GuiContext;
const OsmrWidget = lib.OsmrWidget.QuarterWidget;
const Image = lib.Image;
const math = std.math;
const Color = lib.Image.Pixel;
const Tailwind = lib.Tailwind;

comptime {
    std.debug.assert(@hasDecl(Backend, "SDLBackend"));
}

fn dvui_col_from(col: Color) dvui.Color {
    const r, const g, const b, const a = col.to_rgba_tuple();
    return dvui.Color{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}
fn draw_error_screen(wait_x_seconds: u64) !void {
    {
        var mainbox = dvui.box(@src(), .vertical, .{
            .background = true,
            .expand = .both,
            .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.sky900)) },
            .gravity_x = 0.5,
        });
        defer mainbox.deinit();
        {
            var mbox = dvui.box(@src(), .horizontal, .{
                .background = false,
                .gravity_x = 0.5,
                .expand = .vertical,
                .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.sky600)) },
            });
            defer mbox.deinit();
            dvui.icon(
                @src(),
                "",
                lib.icons.lucide.@"cloud-off",
                .{},
                .{
                    .background = true,
                    .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.teal950)) },
                    .min_size_content = .{ .w = 80, .h = 80 },
                    .margin = .all(50),
                    .padding = .all(15),
                    .corner_radius = .all(20),
                    .gravity_y = 0.5,
                    .expand = .ratio,
                },
            );
        }
        {
            var box2 = dvui.box(@src(), .vertical, .{
                .background = false,
                .gravity_x = 0.5,
                .min_size_content = .{ .h = 150, .w = 500 },
                .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.green600)) },
            });
            defer box2.deinit();
            dvui.label(@src(), "something went wrong . . .\nretrying in {}", .{wait_x_seconds}, .{
                .background = false,
                .color_text = .{ .color = dvui_col_from(.from_hex(Tailwind.neutral50)) },
                .gravity_y = 0.5,
                .min_size_content = dvui.Size{ .w = 400, .h = 200 },
                .font = .{ .name = "sfpro", .size = 42 },
            });
        }
    }
}
const zoom_lower_bound = 6;
const zoom_upper_bound = 14;
const controls = struct {
    fn magnify(ctx: *GuiContext) void {
        ctx.zoom = math.clamp(ctx.zoom + 1, zoom_lower_bound, zoom_upper_bound);
        std.log.warn("zoom is now: {}", .{ctx.zoom});
    }
    fn minify(ctx: *GuiContext) void {
        ctx.zoom = math.clamp(ctx.zoom - 1, zoom_lower_bound, zoom_upper_bound);
        std.log.warn("zoom is now: {}", .{ctx.zoom});
    }
    fn maps(ctx: *GuiContext) void {
        ctx.style = .None;
        std.log.warn("style is now {any}", .{ctx.style});
    }
    fn temp2m(ctx: *GuiContext) void {
        ctx.style = .Temperature;
        std.log.warn("style is now {any}", .{ctx.style});
    }
    fn rain(ctx: *GuiContext) void {
        ctx.style = .Percipitation;
        std.log.warn("style is now {any}", .{ctx.style});
    }
    fn wind(ctx: *GuiContext) void {
        ctx.style = .Wind;
        std.log.warn("style is now {any}", .{ctx.style});
    }
    fn blendmode(ctx: *GuiContext) void {
        // const win = ctx.win orelse return;
        const bm: Image.BlendMode = @enumFromInt(ctx.blendmode);
        // const alloc = win.arena();
        // _ = std.fmt.allocPrint(alloc, "{}", .{bm});
        ctx.blendmode = (ctx.blendmode + 1) % (@typeInfo(Image.BlendMode).@"enum".fields.len);
        std.log.warn("bmode is now: {}", .{bm});
    }

    const style_max: usize = @typeInfo(GuiContext.WeatherStyle).@"enum".fields.len;
    fn next_view(ctx: *GuiContext) void {
        const style_num: usize = @intFromEnum(ctx.style);
        const style_num_adj = (style_num + 1) % style_max;
        ctx.style = @enumFromInt(style_num_adj);
        std.log.warn("style is now {any}", .{ctx.style});
    }
    fn previous_view(ctx: *GuiContext) void {
        const style_num: usize = @intFromEnum(ctx.style);
        const style_num_adj = (style_num + style_max - 1) % style_max;
        ctx.style = @enumFromInt(style_num_adj);
        std.log.warn("style is now {any}", .{ctx.style});
    }
    const weather_points_max: usize = GuiContext.MAX_WEATHER_POINTS;
    fn next_datapoint(ctx: *GuiContext) void {
        ctx.datapoint = (ctx.datapoint + 1) % weather_points_max;
    }
    fn prev_datapoint(ctx: *GuiContext) void {
        ctx.datapoint = (ctx.datapoint + weather_points_max - 1) % weather_points_max;
    }
};
fn handle_keys(ctx: *GuiContext) void {
    const win = ctx.win orelse return;
    for (win.events.items) |ev| {
        switch (ev.evt) {
            .key => |k| {
                if (k.action == .down) {
                    if (k.code == .up or k.code == .k) {
                        controls.magnify(ctx);
                    }
                    if (k.code == .down or k.code == .j) {
                        controls.minify(ctx);
                    }
                    if (k.code == .left or k.code == .h) {
                        controls.previous_view(ctx);
                    }
                    if (k.code == .right or k.code == .l) {
                        controls.next_view(ctx);
                    }
                    if (k.mod.shift() and k.code == .n) {
                        controls.prev_datapoint(ctx);
                    }
                    if (!k.mod.shift() and k.code == .n) {
                        controls.next_datapoint(ctx);
                    }
                    if (k.code == .escape or k.code == .space) {
                        ctx.quit = true;
                    }
                    if (k.code == .w) {
                        controls.wind(ctx);
                    }
                    if (k.code == .t) {
                        controls.temp2m(ctx);
                    }
                    if (k.code == .r or k.code == .p) {
                        controls.rain(ctx);
                    }
                    if (k.code == .m) {
                        controls.maps(ctx);
                    }
                }
            },
            else => {},
        }
    }
}
fn draw_app(ctx: *GuiContext) !void {
    const pool = ctx.pool;
    var __exe = ctx.sched.get_executor(0);
    const as_exec = __exe.async_executor();
    const win = ctx.win orelse return;
    handle_keys(ctx);
    if (win.events.items.len > 0) ctx.inactivity_timer.reset();
    try ctx.update_location();

    const loc = ctx.location.?;
    const lat = loc.lat; // 51.3276;
    const lon = loc.lon; // 12.3884;
    const utc_offset = loc.offset; // 3600 * 2;

    {
        var mainbox = dvui.box(@src(), .horizontal, .{
            .background = false,
            .expand = .both,
            .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.red400)) },
        });
        defer mainbox.deinit();
        // WEATHER
        {
            var weatherbox = dvui.box(@src(), .horizontal, .{
                .rect = mainbox.child_rect,
                .color_fill = .{
                    .color = dvui_col_from(.from_hex(Tailwind.blue300)),
                },
            });
            defer weatherbox.deinit();
            {
                // std.log.warn("main app rect: {any}", .{mainbox.child_rect});
                _ = try ctx.multi_widget.draw(as_exec, pool, weatherbox.child_rect, lat, lon, ctx.zoom, &ctx.datapoint, ctx.style, utc_offset);
            }
        }

        // MENU
        {
            var menubox = dvui.box(@src(), .horizontal, .{
                .background = false,
                .rect = mainbox.child_rect,
                .color_fill = .{ .color = dvui_col_from(.from_hex(Tailwind.orange300)) },
            });
            defer menubox.deinit();

            {
                var ctrlboxbox = dvui.box(@src(), .vertical, .{
                    .corner_radius = .all(5),
                    .background = false,
                    .expand = .vertical,
                    .padding = .all(10),
                });
                defer ctrlboxbox.deinit();
                {
                    var neutral800 = dvui_col_from(.from_hex(Tailwind.neutral800));
                    neutral800.a = 220;
                    var controlbox = dvui.box(@src(), .vertical, .{
                        .color_fill = .{ .color = neutral800 },
                        .corner_radius = .all(5),
                        .background = true,
                        .padding = .all(2),
                        .gravity_y = 0.55,
                    });
                    defer controlbox.deinit();

                    var neutral_50 = dvui_col_from(.from_hex(Tailwind.neutral50));
                    neutral_50.a = 200;

                    const lucide = lib.icons.lucide;
                    const icon_opts = dvui.Options{
                        .min_size_content = .{ .h = 30 },
                        .color_fill = .{ .color = neutral_50 },
                        .color_accent = .{ .color = neutral_50 },
                        .color_fill_hover = .{
                            .color = dvui_col_from(.from_hex(Tailwind.teal500)),
                        },
                    };
                    const icon_render_opts = dvui.IconRenderOptions{ .stroke_width = 1.5 };
                    // magnify
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.@"zoom-in",
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.magnify(ctx);
                    }
                    // minify
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.@"zoom-out",
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.minify(ctx);
                    }
                    // maps
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.map,
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.maps(ctx);
                    }
                    //temperature
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.thermometer,
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.temp2m(ctx);
                    }
                    //rain
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.@"cloud-drizzle",
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.rain(ctx);
                    }
                    //wind
                    if (dvui.buttonIcon(
                        @src(),
                        "",
                        lucide.wind,
                        .{},
                        icon_render_opts,
                        icon_opts,
                    )) {
                        controls.wind(ctx);
                    }
                }
            }
        }
    }
}
var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
var ts_ctx: GuiContext = undefined;
var ts_mutex = std.Thread.Mutex{};
var ts_last_path_absolute: ?[:0]const u8 = null;
var ts_current_desktop: ?[:0]const u8 = null;
const sf_pro_ttf = @embedFile("assets/SF-Pro.ttf");

pub fn main() !void {
    comptime std.debug.assert(@hasDecl(Backend, "SDLBackend"));
    if (@import("builtin").os.tag == .windows) { // optional
        const winapi = struct {
            extern "kernel32" fn AttachConsole(dwProcessId: std.os.windows.DWORD) std.os.windows.BOOL;
        };
        const ATTACH_PARENT_PROCESS: std.os.windows.DWORD = 0xFFFFFFFF; //DWORD(-1)
        const res = winapi.AttachConsole(ATTACH_PARENT_PROCESS);
        if (res == std.os.windows.FALSE) {}
    }

    if (builtin.os.tag == .macos) {
        const c_str = lib.wallpaper.getCurrentWallpaperPathC();
        if (c_str == null) return error.WallPaperError;
        ts_current_desktop = std.mem.span(c_str);
    }
    std.log.info("SDL version: {}", .{Backend.getSDLVersion()});
    defer if (gpa_instance.deinit() != .ok) @panic("Memory leak on exit!");
    const alloc = gpa_instance.allocator();

    var ctx: GuiContext = try GuiContext.init(alloc);
    defer ctx.deinit();
    ts_ctx = try GuiContext.init(alloc);
    defer ts_ctx.deinit();
    const window_icon_png = @embedFile("assets/appicon.png");

    var backend = try Backend.initWindow(.{
        .allocator = alloc,
        .size = .{ .w = 800.0, .h = 600.0 },
        .min_size = .{ .w = 250.0, .h = 350.0 },
        .vsync = true,
        .title = "Weather App Local",
        .icon = window_icon_png, // can also call setIconFromFileContent()
    });

    ctx.backend = backend;
    defer backend.deinit();

    const width = 1200;
    const height = 800;
    const TS = @import("lib/dvui-export.zig");
    var ts = try TS.init(.{
        .allocator = alloc,
        .window_size = .{
            .w = @floatFromInt(width),
            .h = @floatFromInt(height),
        },
    });
    defer ts.deinit();
    var do_export = false;

    var app_win = try dvui.Window.init(@src(), alloc, backend.backend(), .{});
    ctx.win = &app_win;
    defer app_win.deinit();

    var interrupted = false;
    main_loop: while (true) {
        const nstime = app_win.beginWait(interrupted);
        try app_win.begin(nstime);
        const quit = try backend.addAllEvents(&app_win);
        if (quit) break :main_loop;

        _ = Backend.c.SDL_SetRenderDrawColor(backend.renderer, 0, 0, 0, 255);
        _ = Backend.c.SDL_RenderClear(backend.renderer);

        try dvui.addFont("sfpro", sf_pro_ttf, null);

        // main draw fn --------------
        const retry_interval = 15;
        if (ctx.error_timer) |*ti| {
            const tdelta = ti.read() / 1_000_000_000;
            dvui.refresh(dvui.currentWindow(), @src(), null);
            draw_error_screen(retry_interval - tdelta) catch {};
            if (tdelta >= retry_interval)
                ctx.error_timer = null;
        } else {
            draw_app(&ctx) catch |e| {
                switch (e) {
                    error.OutOfMemory => @panic("out of memory"),
                    else => {
                        // if (true) panic("Error {}", .{e});
                        std.log.warn("{}", .{e});
                        dvui.refresh(dvui.currentWindow(), @src(), null);
                        ctx.error_timer = std.time.Timer.start() catch unreachable;
                    },
                }
            };
        }

        // marks end of dvui frame, don't call dvui functions after this
        // - sends all dvui stuff to backend for rendering, must be called before renderPresent()
        const end_micros = try app_win.end(.{});

        // cursor management
        try backend.setCursor(app_win.cursorRequested());
        try backend.textInputRect(app_win.textInputRequested());

        // render frame to OS
        try backend.renderPresent();
        // -----------------------------------------------------------------------------------------

        if (builtin.os.tag == .macos) {
            if (ts_mutex.tryLock()) {
                if (!do_export) do_export = GuiContext.check_if_should_export(&ctx, &ts_ctx);
                // render image
                if (do_export) {
                    try ts.window.begin(0);
                    try dvui.addFont("sfpro", sf_pro_ttf, null);
                    const export_ready = try prepare_export();
                    if (export_ready) {
                        const captured_bytes = try ts.capturePng(export_frame, null);
                        write_screenshot(ts.allocator, ts_ctx.pool, captured_bytes) catch |e| std.log.warn("{}", .{e});
                        do_export = false;
                    }
                    _ = try ts.window.end(.{});
                }
                ts_mutex.unlock();
            }
        }

        // waitTime and beginWait combine to achieve variable framerates
        const wait_event_micros = app_win.waitTime(end_micros, null);
        interrupted = try backend.waitEventTimeout(wait_event_micros);
    }
    try clean_up_export_path(ts.allocator);
    if (ts_current_desktop) |p| {
        if (builtin.os.tag == .macos) {
            _ = lib.wallpaper.setWallpaperOnAllScreensAndSpacesC(p);
        }
    }
    std.debug.print("deinit", .{});
}
pub fn th_write_screenshot(xalloc: Allocator, xcaptured_bytes: []const u8) void {
    const m = struct {
        fn w(gpa: Allocator, captured_bytes: []const u8) !void {
            defer gpa.free(captured_bytes);
            var arena = std.heap.ArenaAllocator.init(gpa);
            defer arena.deinit();
            const alloc = arena.allocator();
            const kind = switch (ts_ctx.style) {
                .None => "map",
                .Percipitation => "rain",
                .Temperature => "temperature",
                .Wind => "wind",
            };
            const file_name = try std.fmt.allocPrint(alloc, "weather_{s}_{}.png", .{ kind, ts_ctx.datapoint });
            try clean_up_export_path(gpa);
            var file = try std.fs.cwd().createFile(file_name, .{});
            var bf = std.io.bufferedWriter(file.writer());
            try bf.writer().writeAll(captured_bytes);
            try bf.flush();
            file.close();
            const path = try std.fs.cwd().realpathAlloc(alloc, file_name);
            const pathz = try alloc.dupeZ(u8, path);
            _ = lib.wallpaper.setWallpaperOnAllScreensAndSpacesC(pathz);
            ts_last_path_absolute = try gpa.dupeZ(u8, path);
        }
    };
    ts_mutex.lock();
    m.w(xalloc, xcaptured_bytes) catch |e| std.log.warn("{}", .{e});
    ts_mutex.unlock();
}

pub fn clean_up_export_path(gpa: Allocator) !void {
    if (ts_last_path_absolute) |abs_path| {
        std.fs.deleteFileAbsolute(abs_path) catch {};
        defer gpa.free(abs_path);
        ts_last_path_absolute = null;
    }
}

pub fn write_screenshot(alloc: Allocator, pool: *std.Thread.Pool, captured_bytes: []const u8) !void {
    try pool.spawn(th_write_screenshot, .{ alloc, captured_bytes });
}

pub fn prepare_export() !bool {
    const loc = ts_ctx.location orelse return false;
    const lat = loc.lat;
    const lon = loc.lon;
    const z = ts_ctx.zoom;
    const style = ts_ctx.style;
    var datapoint = ts_ctx.datapoint;

    const multi_widget = &ts_ctx.multi_widget;

    const vp2 = dvui.windowRectScale().rectFromPhysical(dvui.windowRectPixels());
    // std.log.warn("export rect: {any}", .{vp2});
    var __exe = ts_ctx.sched.get_executor(0);
    const as_exec = __exe.async_executor();

    const res = multi_widget.fetch(as_exec, ts_ctx.pool, vp2, lat, lon, z, &datapoint, style);
    if (res) |_| {} else |e| {
        std.log.warn("{}", .{e});
    }

    const check_weather = (std.meta.eql(multi_widget.weather_widget.upd, .{
        .lat = lat,
        .lon = lon,
        .z = z,
        .style = style,
        .datapoint = datapoint,
    }));
    const check_map = (std.meta.eql(multi_widget.maps_widget.params, .{
        .lat = lat,
        .lon = lon,
        .z = z,
        .stil = switch (style) {
            .None => .color,
            else => .black_and_white,
        },
    }));
    if (check_weather and check_map and multi_widget.weather_widget.legend != null) return true;
    return false;
}

pub fn export_frame() !dvui.App.Result {
    const loc = ts_ctx.location.?;
    const lat = loc.lat;
    const lon = loc.lon;
    const utc_offset = loc.offset;
    const z = ts_ctx.zoom;
    const style = ts_ctx.style;
    var datapoint = ts_ctx.datapoint;
    var __exe = ts_ctx.sched.get_executor(0);
    const as_exec = __exe.async_executor();

    const multi_widget = &ts_ctx.multi_widget;
    const vp2 = dvui.windowRectScale().rectFromPhysical(dvui.windowRectPixels());

    multi_widget.redraw = true;
    try multi_widget.draw(as_exec, ts_ctx.pool, vp2, lat, lon, z, &datapoint, style, utc_offset);
    return .ok;
}

pub fn export_frame2() anyerror!dvui.App.Result {
    const vp = dvui.windowRect();
    const vp2: dvui.Rect = .{
        .w = vp.w,
        .h = vp.h,
        .x = vp.x,
        .y = vp.y,
    };
    dvui.label(@src(), ",", .{}, .{
        .rect = vp2,
        .background = true,
        .color_fill = .fromColor(.red),
    });
    return .ok;
}
