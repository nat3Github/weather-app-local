const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;

const root = @import("root.zig");
const util = root.util;

// TODO: we really want to stay under the api limit of 10 000
// lets say 100 sessions that leaves 100 api calls
// limit the app to a specific grid size where we can guarantee data

// idea: on startup fetch data for the day
// then only fetch outdated data for the current position
// should be much more effcient and still good enough
// daily update for data other than the curent position is acceptable
// therefore store the time range with the data
// store persistant data in a local database
// which gets loaded on startup

pub fn default_instance(comptime T: type) T {
    comptime {
        return switch (@typeInfo(T)) {
            .@"struct" => |st| blk: {
                var x: T = undefined;
                for (st.fields) |f| {
                    const z = &@field(x, f.name);
                    z.* = default_instance(f.type);
                }
                break :blk x;
            },
            .@"enum" => |e| @enumFromInt(e.fields[0].value),
            .pointer => |p| {
                if (p.is_const and p.size == .slice) {
                    return &.{};
                } else @compileLog("not handled");
            },
            else => 0,
        };
    }
}
test "test comptime default" {
    _ = comptime default_instance(WeatherDataRaw);
}

// json parsing struct definitions
// Weather Data Hourly Struct
pub const Minutes15Raw = struct {
    time: []const i64,

    temperature_2m: []const f32,
    apparent_temperature: []const f32,
    // relative_humidity_2m: []const u7,
    precipitation: []const f32, // preceding 15 minute sum
    weather_code: []const u32,
    // cloud_cover: []const u7,
    // snowfall: []const f32,

    wind_speed_10m: []const f32,
    wind_direction_10m: []const u9,
    wind_speed_80m: []const f32,
    wind_direction_80m: []const u9,

    // visibility: []const f32,

    pub const MeteoJsonResult = struct {
        latitude: f32,
        longitude: f32,
        timezone: []const u8,
        utc_offset_seconds: i64,
        minutely_15: Minutes15Raw,
    };

    // LEAKY!!!
    pub fn fetch_multiple(alloc: Allocator, datapoint_count: usize, lat: []const f32, lon: []const f32, max_alloc_bytes: usize) ![]const MeteoJsonResult {
        assert(lat.len == lon.len);
        if (lat.len == 0) return &.{};
        var slist = std.ArrayList(u8).init(alloc);
        try slist.appendSlice("https://api.open-meteo.com/v1/forecast?");

        const lats = "latitude=";
        const lons = "&longitude=";
        try slist.appendSlice(lats);
        try slist.appendSlice(try util.join2048(f32, alloc, lat, util.fmt_coordinate, ","));
        try slist.appendSlice(lons);
        try slist.appendSlice(try util.join2048(f32, alloc, lon, util.fmt_coordinate, ","));

        const minutely_str = comptime util.comma_seperated_from(@typeInfo(Minutes15Raw).@"struct".fields[1..]);
        try slist.appendSlice(std.fmt.comptimePrint("&minutely_15={s}", .{minutely_str}));
        try slist.appendSlice(try std.fmt.allocPrint(alloc, "&forecast_minutely_15={}", .{datapoint_count}));
        try slist.appendSlice("&timeformat=unixtime");

        const api_str = slist.items;
        const uri = try std.Uri.parse(api_str);
        // std.log.warn("{s}", .{api_str});
        if (lat.len == 1) {
            var slc = try alloc.alloc(MeteoJsonResult, 1);
            const data: MeteoJsonResult = try util.http_json_api_to_T_leaky(MeteoJsonResult, alloc, uri, max_alloc_bytes);
            slc[0] = data;
            return slc;
        } else {
            const data: []const MeteoJsonResult = try util.http_json_api_to_T_leaky([]const MeteoJsonResult, alloc, uri, max_alloc_bytes);
            return data;
        }
    }
};

test "fetch forcast points" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    const lat = 52;
    const lon = 12;
    const z_static = 6;
    const order = 8;
    const latlon_arr = try forecast_points_row_major_order(alloc, order, lat, lon, z_static);
    const hours6 = 6 * 4;
    const fetch = try Minutes15Raw.fetch_multiple(alloc, hours6, latlon_arr.lat, latlon_arr.lon, 1024 * 1024 * hours6);
    for (0..math.sqrt(fetch.len)) |i| {
        const time = fetch[i].minutely_15.time;
        std.log.warn("index {}", .{i});
        std.log.warn("start time: {}", .{time[0]});
        std.log.warn("end time: {}", .{time[time.len - 1]});
    }
}
pub fn normalize_latitude(lat: f32) f32 {
    var normalized = lat;
    if (normalized > 90.0) {
        normalized = 180.0 - normalized;
    } else if (normalized < -90.0) {
        normalized = -180.0 - normalized;
    }
    return @min(@max(normalized, -90.0), 90.0);
}
pub fn normalize_latitude2(lat: f32) f32 {
    const sign = math.sign(lat);
    _ = sign;
    const normalized = @mod(lat + 90, 180);
    return normalized - 90;
}

fn normalizeLongitude(lon: f64) f64 {
    var normalized = @mod(lon + 180.0, 360.0);
    if (normalized < 0.0) {
        normalized += 360.0;
    }
    return normalized - 180.0;
}

test "print sruff" {
    const f: f32 = 90;
    const x = normalize_latitude2(f);
    try expect(normalize_latitude2(-91) == 89);
    // try expect(normalize_latitude2(-90) == 90);
    // try expect(normalize_latitude2(90) == 90);

    std.log.warn("x: {d:.3}", .{x});
}

pub fn forecast_points_row_major_order(alloc: Allocator, order: usize, lat: f32, lon: f32, z: u32) !struct { lat: []const f32, lon: []const f32 } {
    const N = 1 + 2 * (order + 1);
    // row major order!
    const lat_arr = try alloc.alloc(f32, N * N);
    const lon_arr = try alloc.alloc(f32, N * N);
    const origin_x, const origin_y = latLonToTileF32(lat, lon, @floatFromInt(z));
    const nminus1f: f32 = @floatFromInt(N - 1);
    for (0..N) |yi| {
        for (0..N) |xi| {
            const idx = xi + N * yi;
            const yif: f32, const xif: f32 = .{ @floatFromInt(yi), @floatFromInt(xi) };
            const ynif: f32, const xnif: f32 = .{ yif / nminus1f, xif / nminus1f };
            const ycnif, const xcnif = .{ ynif - 0.5, xnif - 0.5 };
            const yj, const xj = .{ origin_y + ycnif, origin_x + xcnif };
            const res_lat, const res_lon = tileToLatLonF32(xj, yj, @floatFromInt(z));
            lat_arr[idx] = res_lat;
            lon_arr[idx] = res_lon;
        }
    }
    return .{
        .lat = lat_arr,
        .lon = lon_arr,
    };
}
test "test forecas pointso row major order" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    const lat = 52;
    const lon = 12;
    const z = 6;
    const order = 1; // N = 5;
    const latlon_arr = try forecast_points_row_major_order(alloc, order, lat, lon, z);
    const N = math.sqrt(latlon_arr.lat.len);
    for (0..N) |row| {
        // std.log.warn("row {}:", .{row + 1});
        for (0..N) |x| {
            const idx = row * N + x;
            std.log.debug("lat: {d:.2} lon: {d:.2}", .{ latlon_arr.lat[idx], latlon_arr.lon[idx] });
        }
    }
}

pub const HourlyRaw = struct {
    time: []const []const u8,

    temperature_2m: []const f32,
    apparent_temperature: []const f32,
    // relative_humidity_2m: []const u7,
    precipitation: []const f32,
    precipitation_probability: []const u7,
    weather_code: []const u7,
    cloud_cover: []const u7,
    // snowfall: []const f32,

    wind_speed_10m: []const f32,
    wind_direction_10m: []const u9,
    wind_speed_180m: []const f32,
    wind_direction_180m: []const u9,

    // visibility: []const f32,
};
pub const DailyRaw = struct {
    time: []const []const u8,
    temperature_2m_min: []const f32,
    temperature_2m_max: []const f32,
    apparent_temperature_min: []const f32,
    apparent_temperature_max: []const f32,

    wind_speed_10m_max: []const f32,
    wind_direction_10m_dominant: []const u9,

    precipitation_sum: []const f32,
    weather_code: []const u32,
    precipitation_hours: []const f32,
    sunshine_duration: []const f32, // in s
};

pub const WeatherDataRaw = struct {
    latitude: f32,
    longitude: f32,
    timezone: []const u8,
    utc_offset_seconds: u64,
    hourly: HourlyRaw,
    daily: DailyRaw,
    fn comptime_init(self: *const WeatherDataRaw, alloc: Allocator, T: type, comptime hourly_field_name: []const u8) ![]T {
        const self_hourly = @field(self.*, hourly_field_name);
        const first_field = @field(self_hourly, @typeInfo(T).@"struct".fields[0].name);
        const hourly: []T = try alloc.alloc(T, first_field.len);
        for (hourly, 0..) |*h, i| {
            var hp = T{};
            inline for (@typeInfo(T).@"struct".fields) |f| {
                const hx = &@field(hp, f.name);
                const arr = @field(self_hourly, f.name);
                const val = arr[i];
                if (comptime f.type == WeatherCode) {
                    hx.* = WeatherCode.init(@intCast(val));
                } else {
                    hx.* = arr[i];
                }
            }
            h.* = hp;
        }
        return hourly;
    }
};

// NOTE about resolution:
// weather models resolution ranges from 0.1° ~10km to 0.25° ~25 km
// vector tile zoom levels:
// ex.: zoom 14 => 360° / 2^14 = 0.021°
// aka it doesnt make sense to ask for more than one point
// from z 11 downwards it makes sense
// roughly from z 8 - 11 is most sensible
// => z8 => 5x5 = 25 api calls x 4 = 100 api calls for a
// 4x4 tile

const OpenMeteoConfig = struct {
    forecast_minutely_15: u32 = 48, // 12h
    forecast_days: u32 = 5,
};

const debug_return_default = true;

// NOTE: does not track allocations
pub fn weather_data_raw_leaky(alloc: Allocator, config: OpenMeteoConfig, lat: []const f32, lon: []const f32, max_alloc_bytes: usize) ![]const WeatherDataRaw {
    if (debug_return_default) {
        const slc = try alloc.alloc(WeatherDataRaw, lat.len);
        for (slc) |*s| s.* = comptime default_instance(WeatherDataRaw);
        return slc;
    }
    assert(lat.len == lon.len);
    if (lat.len == 0) return &.{};
    var slist = std.ArrayList(u8).init(alloc);
    try slist.appendSlice("https://api.open-meteo.com/v1/forecast?");
    // a string list corresponds to str1,str2,str3...
    const lats = "latitude=";
    const lons = "&longitude=";
    try slist.appendSlice(lats);
    try slist.appendSlice(try util.join2048(f32, alloc, lat, util.fmt_coordinate, ","));
    try slist.appendSlice(lons);
    try slist.appendSlice(try util.join2048(f32, alloc, lon, util.fmt_coordinate, ","));

    const hourly_str = comptime util.comma_seperated_from(@typeInfo(HourlyRaw).@"struct".fields[1..]);
    const daily_str = comptime util.comma_seperated_from(@typeInfo(DailyRaw).@"struct".fields[1..]);

    const hourlys = std.fmt.comptimePrint("&hourly={s}", .{hourly_str});
    try slist.appendSlice(hourlys);
    const dailys = std.fmt.comptimePrint("&daily={s}", .{daily_str});
    try slist.appendSlice(dailys);

    try slist.appendSlice(std.fmt.comptimePrint("&forecast_days={}", .{config.forecast_days}));
    try slist.appendSlice(std.fmt.comptimePrint("&forecast_minutely_15={}", .{config.forecast_minutely_15}));

    const api_str = slist.items;
    const uri = try std.Uri.parse(api_str);
    std.log.warn("{s}", .{api_str});

    if (lat.len == 1) {
        var slc = try alloc.alloc(WeatherDataRaw, 1);
        const data: WeatherDataRaw = try util.http_json_api_to_T_leaky(WeatherDataRaw, alloc, uri, max_alloc_bytes);
        slc[0] = data;
        return slc;
    } else {
        const data: []const WeatherDataRaw = try util.http_json_api_to_T_leaky([]const WeatherDataRaw, alloc, uri, max_alloc_bytes);
        return data;
    }
}
pub const WeatherCode = enum(u8) {
    ClearSky = 0,
    MainlyClear = 1,
    PartlyCloudy = 2,
    Overcast = 3,

    Fog = 45,
    DepositingRimeFog = 48,

    DrizzleLight = 51,
    DrizzleModerate = 53,
    DrizzleDense = 55,

    FreezingDrizzleLight = 56,
    FreezingDrizzleDense = 57,

    RainSlight = 61,
    RainModerate = 63,
    RainHeavy = 65,

    FreezingRainLight = 66,
    FreezingRainHeavy = 67,

    SnowSlight = 71,
    SnowModerate = 73,
    SnowHeavy = 75,

    SnowGrains = 77,

    RainShowersSlight = 80,
    RainShowersModerate = 81,
    RainShowersViolent = 82,

    SnowShowersSlight = 85,
    SnowShowersHeavy = 86,

    ThunderstormSlightModerate = 95,
    ThunderstormWithHailSlight = 96,
    ThunderstormWithHailHeavy = 99,

    Unknown,
    pub fn init(code: u8) WeatherCode {
        return std.meta.intToEnum(WeatherCode, code) catch .Unknown;
    }
};
test "weather codee" {
    try expect(WeatherCode.init(87) == .Unknown);
    try expect(WeatherCode.init(99) == .ThunderstormWithHailHeavy);
    try expect(WeatherCode.init(75) == .SnowHeavy);
    std.log.info("weather codes ok", .{});
}

pub fn latLonToTileF64(lat_deg: f64, lon_deg: f64, zoom: f64) struct { f64, f64 } {
    const lat_rad = math.degreesToRadians(lat_deg);
    const n = math.pow(f64, 2.0, zoom);

    const x = (lon_deg + 180.0) / 360.0 * n;
    const y = (1.0 - math.log(f64, math.e, math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n;
    return .{ x, y };
}
pub fn latLonToTileF32(lat_deg: f32, lon_deg: f32, zoom: f32) struct { f32, f32 } {
    const lat_rad = math.degreesToRadians(lat_deg);
    const n = math.pow(f32, 2.0, zoom);

    const x = (lon_deg + 180.0) / 360.0 * n;
    const y = (1.0 - math.log(f32, math.e, math.tan(lat_rad) + 1.0 / math.cos(lat_rad)) / math.pi) / 2.0 * n;
    return .{ x, y };
}
pub fn tileToLatLonF32(x: f32, y: f32, z: f32) struct { f32, f32 } {
    const n = math.pow(f32, 2.0, z);
    const lon = x / n * 360.0 - 180.0;
    const lat_rad = math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / n)));
    const lat = math.radiansToDegrees(lat_rad);
    return .{ lat, lon };
}

pub fn tileToLatLonF64(x: f64, y: f64, z: f64) struct { f64, f64 } {
    const n = math.pow(f64, 2.0, z);
    const lon = x / n * 360.0 - 180.0;
    const lat_rad = math.atan(math.sinh(math.pi * (1.0 - 2.0 * y / n)));
    const lat = math.radiansToDegrees(lat_rad);
    return .{ lat, lon };
}

test "test tile lat lon" {
    const lat: f64, const lon: f64, const z: f64 = .{ 52.34, 12.34, 14.0 };
    const resx, const resy = latLonToTileF64(lat, lon, z);
    const coordslat, const coordslon = tileToLatLonF64(resx, resy, z);
    try expect(math.approxEqAbs(f64, coordslat, lat, 1e6));
    try expect(math.approxEqAbs(f64, coordslon, lon, 1e6));
}
