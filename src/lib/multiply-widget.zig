const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");

const dvui = @import("dvui");
const weather = root.weather;
const osmr = @import("osmr");
const fifoasync = @import("fifoasync");
const AsyncExecutor = fifoasync.sched.AsyncExecutor;

const Texture = dvui.Texture;
const Image = root.Image;
const Pixel = Image.Pixel;
const AsFn = fifoasync.sched.ASFunction;
const Task = fifoasync.sched.Task;
const Color = dvui.Color;
const Tailwind = osmr.Tailwind;
const latLonToTileF64 = weather.weather.latLonToTileF64;
const ImageWidget2 = @import("ImageWidget2.zig");
const Cities = @import("cities.zig");
const City = Cities.City;
const latLonToTileF32 = weather.weather.latLonToTileF32;

const Sched = root.GuiContext.Sched;
const MapsWidget = root.OsmrWidget;
const WeatherWidget = root.WeatherWidget;

const MultiplyWidget = @This();

maps_widget: MapsWidget,
weather_widget: WeatherWidget,
cities: Cities,
datapoint: usize = 0,

alloc: Allocator,
img: Image,
redraw: bool = false,
blended: bool = false,
blendmode: ?Image.BlendMode = null,

width: usize = 1024,
height: usize = 1024,

const image_size = 1920;
pub fn init(alloc: Allocator) !@This() {
    return @This(){
        .alloc = alloc,
        .maps_widget = try MapsWidget.init(alloc, image_size),
        .weather_widget = try WeatherWidget.init(alloc, image_size),
        .img = try Image.init(alloc, image_size, image_size),
        .cities = try Cities.init(alloc),
    };
}
pub fn deinit(self: *@This(), _: Allocator) void {
    self.maps_widget.deinit();
    self.weather_widget.deinit();
    self.img.deinit();
    self.cities.deinit();
}
pub fn resize(self: *@This(), width: usize, height: usize) !bool {
    const wh = @max(width, height);
    if (self.weather_widget.state == .Fetch or self.maps_widget.state == .Fetch) return false;
    if (self.height != width or self.width != height) {
        const reset = blk: {
            self.img.resize(wh, wh) catch break :blk true;
            self.weather_widget.img.resize(wh, wh) catch break :blk true;
            self.weather_widget.img2.resize(wh, wh) catch break :blk true;
            self.maps_widget.img.resize(wh, wh) catch break :blk true;
            break :blk false;
        };
        if (reset) {
            self.img.resize(wh, wh) catch unreachable;
            self.weather_widget.img.resize(wh, wh) catch unreachable;
            self.weather_widget.img2.resize(wh, wh) catch unreachable;
            self.maps_widget.img.resize(wh, wh) catch unreachable;
        }
        self.width = width;
        self.height = height;
        return true;
    }
    return false;
}

pub fn fetch(self: *@This(), async_exe: AsyncExecutor, pool: *std.Thread.Pool, view_port: dvui.Rect, lat: f32, lon: f32, z: u32, datapoint: *usize, weather_style: WeatherWidget.WStyle) !struct {
    maps_update: bool,
    weather_update: bool,
} {
    const screen = dvui.currentWindow().screenRectScale(view_port);
    const max_screen_len = @max(screen.r.w, screen.r.h);
    const max_screen_lenu: usize = @intFromFloat(@round(max_screen_len));
    const size_update = try self.resize(max_screen_lenu, max_screen_lenu);
    // MAPS
    const maps_update = try self.maps_widget.fetch(
        pool,
        async_exe,
        .{
            .lat = lat,
            .lon = lon,
            .z = z,
            .stil = switch (weather_style) {
                .None => .color,
                else => .black_and_white,
            },
        },
        size_update,
    );
    // WEATHER
    const weather_update = try self.weather_widget.fetch(
        pool,
        async_exe,
        .{
            .lat = lat,
            .lon = lon,
            .z = z,
            .datapoint = datapoint.*,
            .style = weather_style,
        },
        size_update,
    );
    _ = try self.cities.fetch(async_exe, .{ .lat = lat, .lon = lon, .z = z });
    return .{
        .maps_update = maps_update,
        .weather_update = weather_update,
    };
}
pub fn copy_map_img(self: *@This()) !bool {
    if (self.maps_widget.p) |pimg| {
        assert(pimg.get_width() == self.img.get_width() and pimg.get_height() == self.img.get_height());
        for (0..self.img.get_width()) |x| {
            for (0..self.img.get_height()) |y| {
                self.img.set_pixel(x, y, pimg.get_pixel(x, y));
            }
        }
        ImageWidget2.invalidate(&self.img);
        self.blended = false;
        return false;
    } else return true;
}
pub fn overlay_weather_img(self: *@This(), view_port: dvui.Rect, weather_style: WeatherWidget.WStyle) !void {
    const max_wh = @max(view_port.h, view_port.w);
    const dxr = (max_wh - view_port.w) / max_wh;
    const dyr = (max_wh - view_port.h) / max_wh;
    const dx_offs: usize = @intFromFloat(dxr * 0.5 * @as(f32, @floatFromInt(self.img.get_width())));
    const dy_offs: usize = @intFromFloat(dyr * 0.5 * @as(f32, @floatFromInt(self.img.get_height())));

    switch (weather_style) {
        .None => {},
        else => {
            if (!self.blended) {
                self.blended = true;
                const blendm: Pixel.BlendMode = switch (weather_style) {
                    .None, .Percipitation => .override,
                    .Temperature => .hard_light,
                    .Wind => .multiply,
                };
                for (dx_offs..self.img.get_width() - dx_offs) |x| {
                    for (dy_offs..self.img.get_height() - dy_offs) |y| {
                        const wpx = self.weather_widget.get_img().get_pixel(x, y);
                        const xpx = self.img.get_pixel(x, y);
                        self.img.set_pixel(x, y, wpx.blend_runtime(xpx, blendm, .premultiplied));
                    }
                }
                ImageWidget2.invalidate(&self.img);
            }
        },
    }
}
pub fn draw(self: *@This(), async_exe: AsyncExecutor, pool: *std.Thread.Pool, view_port: dvui.Rect, lat: f32, lon: f32, z: u32, datapoint: *usize, weather_style: WeatherWidget.WStyle, utc_offset: i64) !void {
    const fetch_res = try self.fetch(async_exe, pool, view_port, lat, lon, z, datapoint, weather_style);
    const try_again = self.redraw or fetch_res.maps_update or fetch_res.weather_update;
    var xredraw = false;
    if (try_again) {
        xredraw = try self.copy_map_img();
        try self.overlay_weather_img(view_port, weather_style);
        self.redraw = xredraw;
    }

    try ImageWidget2.draw_square_image_centered_in_rect(&self.img, view_port, 99999);

    // CITY NAMES
    if (true) {
        const upd_cities = try self.cities.fetch(async_exe, .{ .lat = lat, .lon = lon, .z = z });
        _ = upd_cities;
        if (self.cities.cities) |xcities| {
            for (xcities[0..@min(10, xcities.len)], 0..) |cit, i| {
                try draw_city(view_port, cit, i, weather_style);
            }
        }
    }

    // WEATHER LEGEND
    try draw_legend(&self.weather_widget, view_port);
    // CENTER WEATHER TIME AND INFO
    try center_weather_time_and_info(&self.weather_widget, view_port, utc_offset, datapoint);
}
fn center_weather_time_and_info(self: *WeatherWidget, view_port: dvui.Rect, utc_offset: i64, datapoint: *usize) !void {
    const style = self.upd.style;
    if (style == .None) {
        const weather_txt_bg_col = switch (style) {
            .None => dvui_col_from_alpha(.fromHex(Tailwind.white), 120),
            else => Color.fromHex(Tailwind.neutral800),
        };
        var tboxbox = dvui.box(@src(), .{ .dir = .horizontal }, .{
            .rect = view_port,
            .padding = .all(10),
        });
        defer tboxbox.deinit();
        {
            var tbox = dvui.box(@src(), .{ .dir = .vertical }, .{
                .gravity_x = 1,
                .padding = .all(15),
                .color_fill = weather_txt_bg_col,
                .background = true,
                .corner_radius = .all(5),
            });
            defer tbox.deinit();
            {
                const datetime = root.datetime.unixToDateTime(@divTrunc(std.time.milliTimestamp(), 1000) + utc_offset);
                const time_fmt = "{:0>2}:{:0>2}";
                dvui.label(@src(), time_fmt, .{
                    datetime.hour, datetime.minute,
                }, .{
                    .background = false,
                    .color_text = weather_text_color(style),
                    .font = .{ .id = .fromName("sfpro"), .size = 60 },
                });
            }
        }
    } else {
        try self.draw_timeline(view_port, utc_offset, style, datapoint);
    }
}

fn weather_text_color(style: WeatherWidget.Style) dvui.Color {
    return switch (style) {
        .None => .fromHex(Tailwind.neutral900),
        else => .fromHex(Tailwind.white),
    };
}

fn draw_legend(self: *WeatherWidget, view_port: dvui.Rect) !void {
    const style = self.upd.style;
    var neutral800: Color = .fromHex(Tailwind.neutral800);
    neutral800.a = 220;
    const px = 10;
    const py = 10;
    const w = 28;
    const rad = 5;
    const corner_x = view_port.x + view_port.w - px;
    const corner_y = view_port.y + view_port.h - py;
    if (self.legend) |*img| {
        const hf: f32 = @floatFromInt(img.get_height());
        const h = hf / 20.0;
        const lg_height = h * w;
        const r = dvui.Rect{
            .w = w,
            .h = lg_height,
            .x = corner_x - w,
            .y = corner_y - lg_height,
        };
        switch (style) {
            .None => return,
            else => try ImageWidget2.draw_img(@src(), img, r, .{}),
        }
        const arr: []const []const u8, const text_width: f32 = switch (style) {
            .None => .{ &.{}, 0 },
            .Percipitation => .{ weather.render.def_rain.Legend, 95 },
            .Temperature => .{ weather.render.def_temp.Legend, 38 },
            .Wind => .{ weather.render.def_wind.Legend, 82 },
        };
        var brect = dvui.Rect{
            .h = r.h,
            .w = text_width,
            .x = r.x - text_width,
            .y = r.y,
        };
        dvui.label(@src(), "", .{}, .{
            .background = true,
            .color_fill = neutral800,
            .rect = brect,
            .corner_radius = .{ .x = rad, .y = 0, .h = rad, .w = 0 },
        });
        brect.y += 5;
        {
            var kbox = dvui.box(@src(), .{ .dir = .vertical }, .{
                .rect = brect,
            });
            defer kbox.deinit();
            for (arr, 0..) |s, i| {
                // const lrect = dvui.Rect{
                //     .h = w,
                //     .w = text_width,
                //     .x = brect.x,
                //     .y = brect.y + w * @as(f32, @floatFromInt(i)),
                // };
                dvui.label(@src(), "{s}", .{s}, .{
                    // .rect = lrect,
                    .margin = .all(0),
                    .padding = .all(0),
                    .background = false,
                    .id_extra = i,
                    .expand = .vertical,
                    .gravity_x = 0.5,
                    .color_text = .fromHex(Tailwind.white),
                    .font = .{ .id = .fromName("sfpro"), .size = 18 },
                });
            }
        }
    }
}

fn draw_city(view_port: dvui.Rect, cit: City, id: usize, weather_style: WeatherWidget.WStyle) !void {
    const max_wh = @max(view_port.h, view_port.w);
    const dx = 0.5 * (view_port.w - max_wh);
    const dy = 0.5 * (view_port.h - max_wh);
    const col: Color =
        switch (weather_style) {
            .None => .fromHex(Tailwind.neutral800),
            else => .fromHex(Tailwind.white),
        };

    {
        var neutral800: dvui.Color =
            switch (weather_style) {
                .None => .fromHex(Tailwind.neutral50),
                else => .fromHex(Tailwind.neutral800),
            };
        neutral800.a = 120;
        var box2 = dvui.box(@src(), .{ .dir = .vertical }, .{
            .rect = .{
                .w = 300,
                .h = 50,
                .x = cit.x * max_wh + dx - 150,
                .y = cit.y * max_wh + dy - 25,
            },
            .background = false,
            .color_fill = .fromHex(Tailwind.blue300),
            .id_extra = id,
            .padding = .all(0),
            .margin = .all(0),
        });
        defer box2.deinit();
        dvui.label(@src(), "{s}", .{cit.name}, .{
            .padding = null,
            .margin = null,
            .gravity_x = 0.5,
            .gravity_y = 0.5,
            .background = true,
            .corner_radius = .all(5),
            .color_fill = neutral800,
            .id_extra = id,
            .color_text = col,
            .font = .{ .id = .fromName("sfpro"), .size = 22 },
        });
    }
}
fn dvui_col_from_alpha(col: dvui.Color, alpha: u8) dvui.Color {
    return dvui.Color{
        .r = col.r,
        .g = col.g,
        .b = col.b,
        .a = alpha,
    };
}
