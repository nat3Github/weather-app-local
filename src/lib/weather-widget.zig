const std = @import("std");
const assert = std.debug.assert;
const expect = std.debug.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const math = std.math;
const root = @import("../root.zig");

const dvui = @import("dvui");
pub const weather = root.weather.render;
const osmr = @import("osmr");
const fifoasync = @import("fifoasync");

const Texture = dvui.Texture;
const Image = root.Image;
const ASW = fifoasync.sched.ASNode;
const Task = fifoasync.sched.Task;
const Tailwind = osmr.Tailwind;
const latLonToTileF32 = @import("weather").weather.latLonToTileF32;
const ImageWidget2 = @import("ImageWidget2.zig");
const Cache = root.db;
pub const CACHE_NAME = "cache";

const Color = dvui.Color;
pub const Style = enum {
    None,
    Wind,
    Percipitation,
    Temperature,
};

const static_z = 6;
const order = 8; // 19x19

pub fn generate(pool: *std.Thread.Pool, arena: *std.heap.ArenaAllocator, db: *Cache, img: *Image, upd: UpdateParameter) !struct { UpdateParameter, Image, CenterInfo } {
    const lat = upd.lat;
    const lon = upd.lon;
    const style = upd.style;
    const datapoint = upd.datapoint;
    const zf: f32 = @floatFromInt(upd.z);
    const zoom_scaling: f32 = math.pow(f32, 2.0, @max(zf - static_z, 0));
    const alloc = arena.allocator();
    const res = try db.get_or_fetch_weather_data(arena.child_allocator, lat, lon, static_z, order);
    defer res.deinit();
    const N = math.sqrt(res.val.len);
    const scaling = zoom_scaling;
    const center_idx = (N / 2) * N + (N / 2);
    const center_data = res.val[center_idx].minutely_15;

    inline for (@typeInfo(root.weather.weather.Minutes15Raw).@"struct".fields) |field| {
        if (@field(center_data, field.name).len <= datapoint) {
            std.log.warn("data point out of bounds", .{});
            res.deinit();
            return error.DataPointOutOfBounds;
        }
    }
    const duped_center_data = weather.Minutes15Raw{
        .time = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "time"))).pointer.child, center_data.time),
        .temperature_2m = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "temperature_2m"))).pointer.child, center_data.temperature_2m),
        .apparent_temperature = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "apparent_temperature"))).pointer.child, center_data.apparent_temperature),
        .precipitation = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "precipitation"))).pointer.child, center_data.precipitation),
        .weather_code = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "weather_code"))).pointer.child, center_data.weather_code),
        .wind_speed_10m = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "wind_speed_10m"))).pointer.child, center_data.wind_speed_10m),
        .wind_direction_10m = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "wind_direction_10m"))).pointer.child, center_data.wind_direction_10m),
        .wind_speed_80m = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "wind_speed_80m"))).pointer.child, center_data.wind_speed_80m),
        .wind_direction_80m = try arena.child_allocator.dupe(@typeInfo(@TypeOf(@field(center_data, "wind_direction_80m"))).pointer.child, center_data.wind_direction_80m),
    };

    const parts = 32;
    switch (style) {
        .None => unreachable,
        .Temperature => {
            const temperature_2m = try weather.get_row_major_data(alloc, res.val, "temperature_2m", {}, datapoint, N, 0);
            try weather.render_mtex(
                alloc,
                pool,
                img,
                parts,
                weather.temperature,
                .{
                    img,
                    scaling,
                    temperature_2m,
                },
            );
        },
        .Percipitation => {
            const temperature_2m = try weather.get_row_major_data(alloc, res.val, "temperature_2m", {}, datapoint, N, 0);
            const precipitation = try weather.get_row_major_data(alloc, res.val, "precipitation", null, datapoint, N, 0);
            try weather.render_mtex(
                alloc,
                pool,
                img,
                parts,
                weather.rain,
                .{
                    img,
                    scaling,
                    precipitation,
                    temperature_2m,
                },
            );
        },
        .Wind => {
            const wind_speed = try weather.get_row_major_data(alloc, res.val, "wind_speed_10m", null, datapoint, N, 0);
            const wind_angle = try weather.get_row_major_data(alloc, res.val, "wind_direction_10m", weather.u9_to_f32, datapoint, N, 0);
            try weather.render_mtex(
                alloc,
                pool,
                img,
                parts,
                weather.wind_speed_color_map,
                .{
                    img,
                    scaling,
                    wind_speed,
                },
            );
            try weather.wind_pattern2(
                img,
                parts,
                alloc,
                wind_speed,
                wind_angle,
            );
        },
    }
    const pix_size = 20;
    const legend_img = switch (style) {
        .None => unreachable,
        .Temperature => blk: {
            const t = weather.def_temp.Temperature;
            const len = @typeInfo(t).@"struct".decls.len;
            std.log.warn("height: {}", .{len});
            var im = try Image.init(
                arena.child_allocator,
                pix_size,
                pix_size * len,
            );
            weather.legend2(&im, t);
            break :blk im;
        },
        .Percipitation => blk: {
            const t = weather.def_rain.Rain;
            const len = @typeInfo(t).@"struct".decls.len;
            std.log.warn("height: {}", .{len});
            var im = try Image.init(
                arena.child_allocator,
                pix_size,
                pix_size * len,
            );
            weather.legend2(&im, t);
            break :blk im;
        },
        .Wind => blk: {
            const t = weather.def_wind.Wind;
            const len = @typeInfo(t).@"struct".decls.len;
            std.log.warn("height: {}", .{len});
            var im = try Image.init(
                arena.child_allocator,
                pix_size,
                pix_size * len,
            );
            weather.legend2(&im, t);
            break :blk im;
        },
    };
    _ = arena.reset(.free_all);
    return .{ upd, legend_img, CenterInfo{ .data = duped_center_data } };
}

pub const AsyncWeatherGen = fifoasync.sched.ASFunction(generate);
const UpdateParameter = struct {
    lat: f32 = 0,
    lon: f32 = 0,
    z: u32 = 0,
    style: Style = .None,
    datapoint: usize = 0,
};

pub const Minutes15RawDataPoint = struct {
    time: i64 = 0,
    temperature_2m: f32 = 0,
    apparent_temperature: f32 = 0,
    precipitation: f32 = 0,
    weather_code: u32 = 0,
    wind_speed_10m: f32 = 0,
    wind_direction_10m: u9 = 0,
    wind_speed_80m: f32 = 0,
    wind_direction_80m: u9 = 0,
};

pub const WStyle = Style;
const CenterInfo = struct {
    data: ?weather.Minutes15Raw = null,
};
arena: std.heap.ArenaAllocator,
db: Cache,
asw: AsyncWeatherGen = .{},
img: Image,
img2: Image,
img_bool: bool = true,
state: State = .None,
alloc: Allocator,
legend: ?Image = null,

center_info: CenterInfo = CenterInfo{},

upd: UpdateParameter = UpdateParameter{},
const State = enum { None, Fetch };

pub fn get_free_img(self: *@This()) *Image {
    return switch (self.img_bool) {
        false => &self.img,
        true => &self.img2,
    };
}
pub fn get_img(self: *@This()) *Image {
    return switch (!self.img_bool) {
        false => &self.img,
        true => &self.img2,
    };
}
pub fn init(alloc: Allocator, width_height: usize) !@This() {
    return @This(){
        .img = try Image.init(alloc, width_height, width_height),
        .img2 = try Image.init(alloc, width_height, width_height),
        .alloc = alloc,
        .db = try Cache.init(CACHE_NAME),
        .arena = std.heap.ArenaAllocator.init(alloc),
    };
}
pub fn deinit(self: *@This()) void {
    self.asw.join();
    if (self.state == .Fetch) {
        if (self.asw.result().? catch null) |res| {
            const xupd, const im, const info = res;
            self.free();
            self.legend = im;
            self.center_info = info;
            self.img_bool = !self.img_bool;
            self.upd = xupd;
        }
    }
    self.img.deinit();
    self.img2.deinit();
    self.free();
    self.arena.deinit();
    self.db.deinit();
}

pub fn free(self: *@This()) void {
    if (self.legend) |*p| {
        p.deinit();
        self.legend = null;
    }
    if (self.center_info.data) |d| {
        self.alloc.free(d.time);
        self.alloc.free(d.temperature_2m);
        self.alloc.free(d.apparent_temperature);
        self.alloc.free(d.precipitation);
        self.alloc.free(d.weather_code);
        self.alloc.free(d.wind_speed_10m);
        self.alloc.free(d.wind_direction_10m);
        self.alloc.free(d.wind_speed_80m);
        self.alloc.free(d.wind_direction_80m);
    }
}
pub fn fetch(
    self: *@This(),
    pool: *std.Thread.Pool,
    async_exe: anytype,
    upd: UpdateParameter,
    force_update: bool,
) !bool {
    const asw = &self.asw;
    const state = &self.state;
    switch (state.*) {
        .None => {
            if (!std.meta.eql(self.upd, upd) or force_update) {
                if (upd.style == .None) {
                    self.upd = upd;
                    return true;
                }
                state.* = .Fetch;
                try self.asw.call(.{
                    pool,
                    &self.arena,
                    &self.db,
                    self.get_free_img(),
                    upd,
                }, async_exe);
                dvui.refresh(dvui.currentWindow(), @src(), null);
            }
        },
        .Fetch => {
            dvui.refresh(dvui.currentWindow(), @src(), null);
            if (asw.result()) |res| {
                state.* = .None;
                const xupd, const im, const info = try res;
                self.free();
                self.legend = im;
                self.center_info = info;
                self.img_bool = !self.img_bool;
                self.upd = xupd;
                return true;
            }
        },
    }
    return false;
}
/// only works inside dvui begin end calls
pub fn draw(
    self: *@This(),
    view_port: dvui.Rect,
    lat: f32,
    lon: f32,
    z: u32,
    datapoint: usize,
    style: Style,
    id: u32,
) !void {
    if (style == .None) return;
    try self.fetch(lat, lon, z, datapoint, style);
    if (self.p) |img| {
        try ImageWidget2.draw_square_image_centered_in_rect(img, view_port, id);
    }
}
const transparent = Color{ .a = 0x00 };
fn timestrEx(unix: i64) ![]const u8 {
    const cw = dvui.currentWindow();
    const alloc = cw.arena();
    const dtime = root.datetime.unixToDateTime(unix);
    const time_str = am_or_pm: {
        if (dtime.hour > 12) break :am_or_pm try std.fmt.allocPrint(alloc, "{:0>2}.{:0>2}", .{ dtime.hour - 12, dtime.minute });
        break :am_or_pm try std.fmt.allocPrint(alloc, "{:0>2}.{:0>2}", .{ dtime.hour, dtime.minute });
    };
    return time_str;
}

fn timestr(unix: i64) ![]const u8 {
    const cw = dvui.currentWindow();
    const alloc = cw.arena();
    const dtime = root.datetime.unixToDateTime(unix);
    const time_str = am_or_pm: {
        if (dtime.hour > 12) break :am_or_pm try std.fmt.allocPrint(alloc, "{:0>2} PM", .{dtime.hour - 12});
        break :am_or_pm try std.fmt.allocPrint(alloc, "{:0>2} AM", .{dtime.hour});
    };
    return time_str;
}
fn timestr24h_minute(unix: i64) ![]const u8 {
    const cw = dvui.currentWindow();
    const alloc = cw.arena();
    const dtime = root.datetime.unixToDateTime(unix);
    const time_str = try std.fmt.allocPrint(alloc, "{:0>2}.{:0>2}", .{ dtime.hour, dtime.minute });
    return time_str;
}
pub fn get_now_idx(dat: weather.Minutes15Raw) usize {
    const now = @divTrunc(std.time.milliTimestamp(), 1000);
    const k = math.clamp(@divTrunc((now - dat.time[0]), (15 * 60)), 0, @as(i64, @intCast(dat.time.len)));
    const now_idx: usize = @intCast(k);
    return now_idx;
}
pub fn draw_timeline(
    self: *@This(),
    view_port: dvui.Rect,
    utc_offset: i64,
    weatherstyle: Style,
    datapoint: *usize,
) !void {
    var timeline_rec = view_port;
    timeline_rec.h = view_port.h / 6;
    timeline_rec.y = 15;
    var box = dvui.box(@src(), .{ .dir = .horizontal }, .{ .rect = timeline_rec });
    defer box.deinit();
    if (self.center_info.data) |dat| {
        const now_idx = get_now_idx(dat);
        const curr_dat = switch (weatherstyle) {
            .None => unreachable,
            .Percipitation => dat.precipitation,
            .Wind => dat.wind_speed_10m,
            .Temperature => dat.temperature_2m,
        };
        const min, const max = std.mem.minMax(f32, curr_dat);
        const range = max - min;

        const start_index = get_start: {
            for (dat.time, 0..) |d, i| {
                const dtime = root.datetime.unixToDateTime(d + utc_offset);
                if (dtime.minute == 0) break :get_start i;
            }
            unreachable;
        };

        const dx = timeline_rec.w / @as(f32, @floatFromInt(dat.time.len));
        for (curr_dat, 0..) |cdat, i| {
            // std.log.warn("{d:.3}", .{cdat});
            const y = (cdat - min) / range;
            dvui.icon(
                @src(),
                "",
                root.icons.lucide.@"circle-stop",
                .{},
                .{
                    .rect = dvui.Rect{
                        .w = 10,
                        .h = 10,
                        .x = dx * @as(f32, @floatFromInt(i)) + dx / 2 - 5,
                        .y = timeline_rec.y + timeline_rec.h - y * timeline_rec.h,
                    },
                    .id_extra = i,
                },
            );
        }

        var j: usize = 0;
        const dist = 3; //hours
        if (dat.time.len == 0) return;
        while (j + start_index < dat.time.len) : (j += 4 * dist) {
            try whitebox_text(
                @src(),
                "{s}",
                .{try timestr24h_minute(dat.time[j + start_index] + utc_offset)},
                dx * @as(f32, @floatFromInt(j + start_index)),
                timeline_rec.y,
                j,
            );
        }
        var red: Color = .fromHex(Tailwind.indigo700);
        red.a = 160;
        var white: Color = .fromHex(Tailwind.sky700);
        var black: Color = .fromHex(Tailwind.stone700);
        black.a = 120;
        white.a = 160;
        for (dat.time, 0..) |_, i| {
            var fill: Color = transparent;
            if (datapoint.* == i) fill = white;
            if (now_idx == i) fill = red;
            if (dvui.button(@src(), "", .{}, .{
                .padding = .all(0),
                .margin = .all(0),
                .background = true,
                .color_fill = fill,
                // .color_fill_hover = black,
                .color_accent = transparent,
                .id_extra = i,
                .rect = dvui.Rect{
                    .h = timeline_rec.h,
                    .w = dx,
                    .y = timeline_rec.y,
                    .x = dx * @as(f32, @floatFromInt(i)),
                },
            })) {
                datapoint.* = i;
            }
        }
        dvui.label(@src(), "Now", .{}, .{
            .background = false,
            .color_text = .fromHex(Tailwind.neutral900),
            .font = .{ .id = .fromName("sfpro"), .size = 22 },
            .id_extra = j,
            .rect = dvui.Rect{
                .h = timeline_rec.h,
                .w = 100,
                .y = timeline_rec.y + timeline_rec.h / 2,
                .x = dx * @as(f32, @floatFromInt(now_idx)),
            },
        });
        try whitebox_text(
            @src(),
            "{s}",
            .{try timestr24h_minute(dat.time[datapoint.*] + utc_offset)},
            dx * @as(f32, @floatFromInt(datapoint.*)),
            timeline_rec.y + timeline_rec.h,
            0,
        );
    }
}
fn whitebox_text(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype, x: f32, y: f32, idx: usize) !void {
    var twhite = Color.fromHex(Tailwind.neutral50);
    twhite.a = 120;
    var box2 = dvui.box(src, .{ .dir = .vertical }, .{
        .rect = .{
            .w = 300,
            .h = 40,
            .x = x,
            .y = y,
        },
        .id_extra = 2 * idx,
        .background = false,
        .padding = .all(0),
        .margin = .all(0),
    });
    defer box2.deinit();
    dvui.label(@src(), fmt, args, .{
        .id_extra = idx,
        .padding = .all(3),
        .margin = null,
        .gravity_x = 0,
        .gravity_y = 0,
        .background = true,
        .corner_radius = .all(4),
        .color_fill = twhite,
        .color_text = .fromHex(Tailwind.neutral900),
        .font = .{ .id = .fromName("sfpro"), .size = 22 },
    });
}
