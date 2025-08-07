const std = @import("std");
const fmt = std.fmt;
const math = std.math;
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Type = std.builtin.Type;
const Allocator = std.mem.Allocator;
const root = @import("root.zig");
const weather = root.weather;
const z2d = root.z2d;
const Image = root.Image;
const tailwind = @import("tailwind");

const lip = @import("interpolation2.zig");
const RowMajorIter = lip.RowMajorIter;
const MeteoJsonResult = weather.Minutes15Raw.MeteoJsonResult;
pub const Minutes15Raw = weather.Minutes15Raw;
const comm = @import("rendercommon.zig");
pub const interpolate = comm.interpolate;
pub const interpolate_angle = comm.interpolate_angle;
pub const plateau_anti_alias_color = comm.plateau_anti_alias_color;
pub const alpha_0to1_to_u8 = comm.alpha_0to1_to_u8;
pub const get_row_major_data = comm.get_row_major_data;
pub const create_random_data = comm.create_random_data;
pub const render_tile_mt = comm.render_tile_mt;
pub const render_mtex = comm.render_mtex;
pub const u9_to_f32 = comm.u9_to_f32;

pub const def_temp = struct {
    const dat = &extract(struct { f32, u8 }, &.{
        Temperature.blue950,
        Temperature.sky900,
        Temperature.cyan700,
        Temperature.cyan500,
        Temperature.teal300,
        Temperature.emerald400,
        Temperature.green500,
        Temperature.lime400,
        Temperature.yellow400,
        Temperature.orange400,
        Temperature.red500,
        Temperature.rose700,
        Temperature.red800,
    }, ex);
    fn ex(x: struct { f32, u8 }) f32 {
        return x.@"0";
    }
    pub fn legend(
        img: *Image,
    ) void {
        for (0..img.get_height()) |y| {
            for (0..img.get_width()) |x| {
                const speed = lip.bicubic_interpolate(dat, 1, dat.len, img.get_width(), img.get_height(), @intCast(x), @intCast(y));
                const col = plateau_anti_alias_color(Temperature, speed, 4);
                const pix = Image.Pixel.init_from_u8_slice(col[0..3]);
                img.set_pixel(x, y, pix);
            }
        }
    }
    pub const Legend = &.{
        "-15°",
        "-10°",
        "-5°",
        "0°",
        "5°",
        "10°",
        "15°",
        "20°",
        "25°",
        "30°",
        "35°",
        "40°",
        "45°",
    };
    pub const alpha = 255;
    pub const Temperature = struct {
        pub const blue950: struct { f32, u8 } = .{ -15.0, alpha };
        pub const sky900: struct { f32, u8 } = .{ -10.0, alpha };
        pub const cyan700: struct { f32, u8 } = .{ -5.0, alpha };
        pub const cyan500: struct { f32, u8 } = .{ 0.0, alpha };
        pub const teal300: struct { f32, u8 } = .{ 5.0, alpha };
        pub const emerald400: struct { f32, u8 } = .{ 10.0, alpha };
        pub const green500: struct { f32, u8 } = .{ 15.0, alpha };
        pub const lime400: struct { f32, u8 } = .{ 20.0, alpha };
        pub const yellow400: struct { f32, u8 } = .{ 25.0, alpha };
        pub const orange400: struct { f32, u8 } = .{ 30.0, alpha };
        pub const red500: struct { f32, u8 } = .{ 35.0, alpha };
        pub const rose700: struct { f32, u8 } = .{ 40.0, alpha };
        pub const red800: struct { f32, u8 } = .{ 45.0, alpha };
    };
};
pub fn temperature(
    img: *Image,
    scaling: f32,
    data: []const f32,
    xoffset: usize,
    yoffset: usize,
) void {
    const N = math.sqrt(data.len);
    assert(N * N == data.len);
    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            const val = interpolate(data, @floatFromInt(img.get_width()), scaling, x + xoffset, y + yoffset);
            const col_rgba = plateau_anti_alias_color(def_temp.Temperature, val, 8);
            const pix = Image.Pixel.init_from_u8_slice(&col_rgba);
            img.set_pixel(x, y, pix);
        }
    }
}
pub const def_rain = struct {
    // from https://en.wikipedia.org/wiki/Rain#:~:text=Moderate%20rain%20%E2%80%94%20when%20the%20precipitation,mm%20(2.0%20in)%20per%20hour
    // from the section "intensity"
    // Light rain — when the precipitation rate is < 2.5 mm (0.098 in) per hour
    // Moderate rain — when the precipitation rate is between 2.5–7.6 mm or 10 mm per hour[116][117]
    // Heavy rain — when the precipitation rate is > 7.6 mm per hour,[116] or between 10 and 50 mm per hour[117]
    // Violent rain — when the precipitation rate is > 50 mm per hour[117]
    const transparent: u8 = 255;
    const light: u8 = 255;
    const moderate: u8 = 255;
    const heavy: u8 = 255;
    const violent: u8 = 255;
    pub const Legend = &.{
        "> 12 mm/h *", // violent snow
        "> 7.6 mm/h *", // heavy snow
        "> 1.2 mm/h *", // moderate snow
        "< 1.2 mm/h *", // light snow
        "no rain", // no rain
        "< 1.2 mm/h", // light rain
        "> 1.2 mm/h", // moderate rain
        "> 7.6 mm/h", // heavy rain
        "> 12 mm/h", // violent rain
    };
    // https://www.weather.gov/lox/rainrate
    pub const Rain = struct {
        pub const rose300: struct { f32, u8 } = .{ -12, violent }; // violent snow
        pub const orange300: struct { f32, u8 } = .{ -7.6, heavy }; // heavy snow
        pub const amber200: struct { f32, u8 } = .{ -1.2, moderate }; // moderate snow
        pub const yellow100: struct { f32, u8 } = .{ -0.1, light }; // light snow
        pub const white: struct { f32, u8 } = .{ 0.1, transparent }; // no rain
        pub const cyan100: struct { f32, u8 } = .{ 1.2, light }; // light rain
        pub const sky300: struct { f32, u8 } = .{ 7.6, moderate }; // moderate rain
        pub const blue400: struct { f32, u8 } = .{ 12, heavy }; // heavy rain
        pub const violet600: struct { f32, u8 } = .{ 30, violent }; // violent rain
    };
};

pub fn rain(
    img: *Image,
    scaling: f32,
    data_percipitation: []const f32,
    data_temperature: []const f32,
    xoffset: usize,
    yoffset: usize,
) void {
    assert(data_percipitation.len == data_temperature.len);
    const N = math.sqrt(data_percipitation.len);
    assert(N * N == data_percipitation.len);
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {
            seed = 12393223498;
        };
        break :blk seed;
    });
    const rand = prng.random();
    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            const percip = interpolate(data_percipitation, @floatFromInt(img.get_width()), scaling, x + xoffset, y + yoffset);
            const temp = interpolate(data_temperature, @floatFromInt(img.get_width()), scaling, x + xoffset, y + yoffset);

            const percip_adj: f32 = @max(0, percip) * 4; // times 4 because this is sum in 15 minutes but the reference is for sum in 60 minutes!
            var val = percip_adj;
            const r = rand.float(f32) - 0.5;
            if (math.sign(temp + r * 2) < 0) val = percip * -1;

            var col_rgba: [4]u8 = undefined;
            if (percip_adj < 0.1) {
                col_rgba = .{ 255, 255, 255, 255 };
            } else {
                col_rgba = plateau_anti_alias_color(def_rain.Rain, val, 8);
            }
            const pix = Image.Pixel.init_from_u8_slice(&col_rgba);
            img.set_pixel(x, y, pix);
        }
    }
}
pub const def_wind = struct {
    // https://en.wikipedia.org/wiki/Beaufort_scale
    // this is read as .{< x kmh, beaufort scale integer}
    pub const BeaufortScale = struct {
        const calm: struct { f32, f32 } = .{ 1, 0 };
        const light_air: struct { f32, f32 } = .{ 5, 1 };
        const light_breeze: struct { f32, f32 } = .{ 11, 2 };
        const gentle_breeze: struct { f32, f32 } = .{ 20, 3 };
        const moderate_breeze: struct { f32, f32 } = .{ 29, 4 };
        const fresh_breeze: struct { f32, f32 } = .{ 39, 5 };
        const strong_breeze: struct { f32, f32 } = .{ 50, 6 };
        const moderate_gale: struct { f32, f32 } = .{ 62, 7 };
        const fresh_gale: struct { f32, f32 } = .{ 75, 8 };
        const strong_gale: struct { f32, f32 } = .{ 89, 9 };
        const storm: struct { f32, f32 } = .{ 103, 10 };
        const violent_storm: struct { f32, f32 } = .{ 118, 11 };
        const hurricane_force: struct { f32, f32 } = .{ 150, 12 };
    };
    pub const Legend = &.{
        "< 1 km/h",
        "< 5 km/h",
        "< 11 km/h",
        "< 20 km/h",
        "< 29 km/h",
        "< 39 km/h",
        "< 50 km/h",
        "< 62 km/h",
        "< 75 km/h",
        "< 89 km/h",
        "< 103 km/h",
        "< 118 km/h",
        "> 118 km/h",
    };
    pub const Wind = struct {
        pub const white = BeaufortScale.calm;
        pub const cyan100 = BeaufortScale.light_air;
        pub const teal200 = BeaufortScale.light_breeze;
        pub const green300 = BeaufortScale.gentle_breeze;
        pub const lime300 = BeaufortScale.moderate_breeze;
        pub const lime500 = BeaufortScale.fresh_breeze;
        pub const yellow400 = BeaufortScale.strong_breeze;
        pub const orange500 = BeaufortScale.moderate_gale;
        pub const red600 = BeaufortScale.fresh_gale;
        pub const fuchsia900 = BeaufortScale.strong_gale;
        pub const violet950 = BeaufortScale.storm;
        pub const rose950 = BeaufortScale.violent_storm;
        pub const slate950 = BeaufortScale.hurricane_force;
    };
};

pub fn wind_pattern_catch_return(
    img: *Image,
    scaling: f32,
    alloc: Allocator,
    data_wind_speed: []const f32,
    data_wind_angle: []const f32,
    xoffset: usize,
    yoffset: usize,
) void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    wind_pattern(
        img,
        scaling,
        arena.allocator(),
        data_wind_speed,
        data_wind_angle,
        xoffset,
        yoffset,
    ) catch {};
    return;
}

const mArrow = struct {
    const Vec2 = struct {
        x: f32,
        y: f32,
    };

    const Arrow = struct {
        shaftStart: Vec2,
        shaftEnd: Vec2,
        headA: Vec2,
        headB: Vec2,
        headC: Vec2,
        pub fn draw(degree: f32, len: f32, size: f32, cx: f32, cy: f32) Arrow {
            const rad = degree * math.pi / 180.0;
            const dirX = math.cos(rad);
            const dirY = math.sin(rad);

            const halfLen = len / 2.0;
            const start = Vec2{
                .x = cx - dirX * halfLen,
                .y = cy - dirY * halfLen,
            };
            const end = Vec2{
                .x = cx + dirX * halfLen * 0.5,
                .y = cy + dirY * halfLen * 0.5,
            };
            const end2 = Vec2{
                .x = cx + dirX * halfLen,
                .y = cy + dirY * halfLen,
            };

            const backX = end2.x - dirX * size;
            const backY = end2.y - dirY * size;
            const perpX = -dirY;
            const perpY = dirX;

            const left = Vec2{
                .x = backX + perpX * size * 0.5,
                .y = backY + perpY * size * 0.5,
            };
            const right = Vec2{
                .x = backX - perpX * size * 0.5,
                .y = backY - perpY * size * 0.5,
            };
            return Arrow{
                .shaftStart = start,
                .shaftEnd = end,
                .headA = left,
                .headB = end2,
                .headC = right,
            };
        }
        fn in_bounds(self: @This()) bool {
            const fields = @typeInfo(@This()).@"struct".fields;
            inline for (fields) |f| {
                const k = @field(self, f.name);
                if (k.x < 0 or k.y < 0) {
                    return false;
                }
            }
            return true;
        }
    };

    fn draw_arrow(ctx: *z2d.Context, degree: f32, cx: f32, cy: f32, len: f32, size: f32) !void {
        const ar = Arrow.draw(degree, len, size, cx, cy);
        try ctx.moveTo(ar.shaftStart.x, ar.shaftStart.y);
        try ctx.lineTo(ar.shaftEnd.x, ar.shaftEnd.y);
        try ctx.stroke();
        ctx.resetPath();

        try ctx.moveTo(ar.headA.x, ar.headA.y);
        try ctx.lineTo(ar.headB.x, ar.headB.y);
        try ctx.lineTo(ar.headC.x, ar.headC.y);
        try ctx.closePath();
        try ctx.fill();
        ctx.resetPath();
    }
};
pub fn wind_pattern2(
    img: *Image,
    scaling: f32,
    alloc: Allocator,
    data_wind_speed: []const f32,
    data_wind_angle: []const f32,
) !void {
    assert(data_wind_speed.len == data_wind_angle.len);
    const K = math.sqrt(data_wind_speed.len);
    assert(K * K == data_wind_speed.len);

    var sfc = try z2d.Surface.initPixel(
        .{
            .rgba = z2d.pixel.RGBA.fromClamped(0, 0, 0, 0),
        },
        alloc,
        @intCast(img.get_width()),
        @intCast(img.get_height()),
    );
    defer sfc.deinit(alloc);
    var ctx = z2d.Context.init(alloc, &sfc);
    defer ctx.deinit();

    const arrow_len = 40;
    const img_size = img.get_width();
    const img_size_f32: f32 = @floatFromInt(img.get_width());
    const N = img_size / arrow_len + 1;
    const Nf32: f32 = @floatFromInt(N);
    const row_major_flag = try alloc.alloc(bool, N * N);
    defer alloc.free(row_major_flag);
    const flag = RowMajorIter(bool).init(row_major_flag, N, N);
    var nextx: f32 = 0;
    var nexty: f32 = 0;
    const dx = img_size_f32 / (Nf32 - 1);
    const m = struct {
        fn point_to_index(f: f32, jdx: f32) usize {
            return @intFromFloat(f / jdx);
        }
        fn index_to_point(j: usize, jdx: f32) f32 {
            const jf32: f32 = @floatFromInt(j);
            return jdx * jf32;
        }
    };
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch break :blk 12304321421401;
        break :blk seed;
    });
    const rand = prng.random();
    const rfac: f32 = 0.5; // random spread
    const dfac: f32 = 1.5; // distance multiplier along a path
    for (0..N * N) |_| {
        const markx = m.point_to_index(nextx, dx);
        const marky = m.point_to_index(nexty, dx);
        flag.get_row_major(markx, marky).* = true;

        const xu: usize = @intFromFloat(nextx);
        const yu: usize = @intFromFloat(nexty);
        const degree = interpolate_angle(data_wind_angle, img_size_f32, scaling, xu, yu);
        const speed = interpolate(data_wind_speed, img_size_f32, scaling, xu, yu);
        // const bf_norm = (@as(f32, @floatFromInt(bf_scale)) / 12);
        const bf_norm = math.clamp(speed, 0, 118) / 118;
        const bf_norm_inv = 1 - bf_norm;
        const bf_fac = 0.7;
        const alen = dx * (bf_fac + bf_norm * bf_fac);
        const line_width = 2 + bf_norm * 1;
        ctx.setLineWidth(line_width);
        const bfnorm_sq = math.pow(f32, bf_norm, 0.75);
        const arrow_size = 8 + bf_norm * 4;
        const alpha: f32 = 0.3 + 0.8 * bfnorm_sq;
        ctx.setSourceToPixel(.{
            .rgba = z2d.pixel.RGBA.fromClamped(
                0.0,
                0.0,
                0.0,
                alpha,
            ),
        });
        if (!(rand.float(f32) < math.pow(f32, bf_norm_inv, 2) * 0.7)) {
            try mArrow.draw_arrow(&ctx, degree, nextx, nexty, alen, arrow_size);
        }

        const rad = degree * math.pi / 180.0;
        const dirX = math.cos(rad);
        const dirY = math.sin(rad);

        nextx += dx * dirX * dfac;
        nexty += dx * dirY * dfac;

        nextx += math.clamp((rand.float(f32) - 0.5) * dx * rfac, 0, Nf32 - 0.5);
        nexty += math.clamp((rand.float(f32) - 0.5) * dx * rfac, 0, Nf32 - 0.5);

        // std.log.warn("next pos: {d:.0}, {d:.0}", .{ nextx, nexty });
        if (nextx < 0 or nextx > img_size_f32 or nexty < 0 or nexty > img_size_f32 or blk: {
            const flgidx_x = m.point_to_index(nextx, dx);
            const flgidx_y = m.point_to_index(nexty, dx);
            break :blk flag.get_row_major(flgidx_x, flgidx_y).*;
        }) {
            _ = find_new_point: {
                for (0..N) |y| {
                    for (0..N) |x| {
                        if (!(flag.get_row_major(x, y).*)) {
                            nextx = m.index_to_point(x, dx);
                            nexty = m.index_to_point(y, dx);
                            // std.log.warn("newpoint: {d:.0}, {d:.0}", .{ nextx, nexty });
                            // std.log.warn("flagixd {} {}", .{ x, y });
                            break :find_new_point;
                        }
                    }
                }
            };
        }
    }

    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            const opix = img.get_pixel(x, y);
            const z2dpix = sfc.getPixel(@intCast(x), @intCast(y)).?.rgba;
            const z2dpixcol = Image.Pixel.init_from_rgba_tuple(.{
                z2dpix.r,
                z2dpix.g,
                z2dpix.b,
                z2dpix.a,
            });
            const blend = opix.blend(z2dpixcol, .override, .premultiplied);
            img.set_pixel(x, y, blend);
        }
    }
}
pub fn wind_pattern(
    img: *Image,
    scaling: f32,
    alloc: Allocator,
    data_wind_speed: []const f32,
    data_wind_angle: []const f32,
    xoffset: usize,
    yoffset: usize,
) !void {
    //NOTE: no support for x offset for now!!
    assert(xoffset == 0);
    assert(yoffset <= img.get_width());
    assert(data_wind_speed.len == data_wind_angle.len);
    const K = math.sqrt(data_wind_speed.len);
    assert(K * K == data_wind_speed.len);

    var sfc = try z2d.Surface.initPixel(
        .{
            .rgba = z2d.pixel.RGBA.fromClamped(0, 0, 0, 0),
        },
        alloc,
        @intCast(img.get_width()),
        @intCast(img.get_height()),
    );
    defer sfc.deinit(alloc);
    var ctx = z2d.Context.init(alloc, &sfc);
    defer ctx.deinit();

    const arrow_len = 40;
    const img_size = img.get_width();
    const img_width_f32: f32 = @floatFromInt(img.get_width());
    const N = img_size / arrow_len + 1;

    const Nystart = (N * yoffset) / img.get_width();
    const Nylen = (N * img.get_height()) / img_size + 2;
    const Nyend = @max(N, Nystart + Nylen);

    for (Nystart..Nyend) |yi| {
        for (0..N) |xi| {
            const dx = @as(f32, img_width_f32) / @as(f32, @floatFromInt(N - 1));
            const cx = @as(f32, @floatFromInt(xi)) * dx;
            const cy = @as(f32, @floatFromInt(yi)) * dx;
            const xu: usize = @intFromFloat(cx);
            const yu: usize = @intFromFloat(cy);
            const degree = interpolate_angle(data_wind_angle, img_width_f32, scaling, xu, yu);
            const speed = interpolate(data_wind_speed, img_width_f32, scaling, xu, yu);
            const col = plateau_anti_alias_color(def_wind.Wind, speed, 4);
            const bf_scale = col[3];
            const bf_norm = (@as(f32, @floatFromInt(bf_scale)) / 12);
            const bf_fac = 0.5;
            const alen = dx * (bf_fac + bf_norm * bf_fac);

            const line_width = 2 + bf_norm * 1;
            ctx.setLineWidth(line_width);
            const arrow_size = 8 + bf_norm * 4;
            ctx.setSourceToPixel(.{
                .rgba = z2d.pixel.RGBA.fromClamped(
                    0.0,
                    0.0,
                    0.0,
                    1.0,
                ),
            });
            const off_x = @as(f32, @floatFromInt(xoffset));
            const off_y = @as(f32, @floatFromInt(yoffset));
            try mArrow.draw_arrow(&ctx, degree, cx - off_x, cy - off_y, alen, arrow_size);
        }
    }
    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            const opix = img.get_pixel(x, y);
            const z2dpix = sfc.getPixel(@intCast(x), @intCast(y)).?.rgba;
            const z2dpixcol = Image.Pixel.init_from_rgba_tuple(.{
                z2dpix.r,
                z2dpix.g,
                z2dpix.b,
                z2dpix.a,
            });
            const blend = opix.blend(z2dpixcol, .override, .premultiplied);
            img.set_pixel(x, y, blend);
        }
    }
}
pub fn wind_speed_angle2(
    img: *Image,
    scaling: f32,
    alloc: Allocator,
    data_wind_speed: []const f32,
    data_wind_angle: []const f32,
) void {
    wind_speed_color_map(img, scaling, data_wind_speed, 0, 0);
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    wind_pattern2(img, scaling, alloc, data_wind_speed, data_wind_angle) catch {};
    return;
}
pub fn wind_speed_angle(
    img: *Image,
    scaling: f32,
    alloc: Allocator,
    data_wind_speed: []const f32,
    data_wind_angle: []const f32,
    xoffset: usize,
    yoffset: usize,
) void {
    wind_speed_color_map(img, scaling, data_wind_speed, xoffset, yoffset);
    wind_pattern_catch_return(img, scaling, alloc, data_wind_speed, data_wind_angle, xoffset, yoffset);
    return;
}

test "wind angle" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    const img_size = 1200;
    var img = try Image.init(alloc, img_size, img_size);
    const datapoints = 1;
    const N = 3 + 2 * 8;
    var benchmark_timer = std.time.Timer.start() catch unreachable;
    const fake_data = try create_random_data(alloc, N, datapoints);
    const datapoint = 0;
    const wind_speed = try get_row_major_data(alloc, fake_data, "wind_speed_10m", null, datapoint, N, 0);
    const wind_angle = try get_row_major_data(alloc, fake_data, "wind_direction_10m", u9_to_f32, datapoint, N, 0);

    const MS = 1_000_000;
    comptime var scaling = 1.0;
    scaling = 1.1;
    try render_tile_mt(alloc, &img, wind_speed_angle, .{
        &img,
        scaling,
        gpa,
        wind_speed,
        wind_angle,
    });
    std.log.warn("temp {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/wind-mt-{d:.1}.ppm", .{scaling}));
    wind_speed_angle2(
        &img,
        scaling,
        gpa,
        wind_speed,
        wind_angle,
    );
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/wind-{d:.1}.ppm", .{scaling}));
}
pub fn wind_speed_color_map(
    img: *Image,
    scaling: f32,
    data_wind_speed: []const f32,
    xoffset: usize,
    yoffset: usize,
) void {
    const K = math.sqrt(data_wind_speed.len);
    assert(K * K == data_wind_speed.len);
    for (0..img.get_height()) |y| {
        for (0..img.get_width()) |x| {
            const speed = interpolate(data_wind_speed, @floatFromInt(img.get_width()), scaling, x + xoffset, y + yoffset);
            const col = plateau_anti_alias_color(def_wind.Wind, speed, 4);
            const pix = Image.Pixel.init_from_u8_slice(col[0..3]);
            img.set_pixel(x, y, pix);
        }
    }
}

pub fn legend2(img: *Image, T: type) void {
    const decls = @typeInfo(T).@"struct".decls;
    const hf: f32 = @floatFromInt(img.get_height());
    const numf: f32 = @floatFromInt(decls.len);
    const dyf = hf / numf;
    inline for (decls, 0..) |b, i| {
        const xif: f32 = @floatFromInt(i);
        const start = xif * dyf;
        const end = (xif + 1) * dyf;
        const startu: f32 = math.clamp(start, 0, hf);
        const endu: f32 = math.clamp(end, 0, hf);
        for (@intFromFloat(startu)..@intFromFloat(endu)) |y| {
            for (0..img.get_width()) |x| {
                const col = root.Image.Pixel.from_hex(@field(tailwind, b.name));
                img.set_pixel(x, y, col);
            }
        }
    }
}
pub fn extract(T: type, comptime arr: []const T, fnc: fn (T) f32) [arr.len]f32 {
    comptime {
        var rarr: [arr.len]f32 = undefined;
        for (
            &rarr,
            arr,
        ) |*a, b| {
            a.* = fnc(b);
        }
        return rarr;
    }
}
test "legend" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    // interpolate to img size
    const img_size = 600;

    var img = try Image.init(alloc, 100, img_size);
    legend2(&img, def_rain.Rain);
    try img.write_ppm_to_file("test/legend-wind.ppm");
}

test "viz" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    // interpolate to img size
    const img_size = 600;

    var img = try Image.init(alloc, img_size, img_size);
    const datapoints = 1;
    const N = 3 + 2 * 8;
    var benchmark_timer = std.time.Timer.start() catch unreachable;

    const fake_data = try create_random_data(alloc, N, datapoints);

    const datapoint = 0;
    const precipitation = try get_row_major_data(alloc, fake_data, "precipitation", null, datapoint, N, 0);

    const wind_speed = try get_row_major_data(alloc, fake_data, "wind_speed_10m", null, datapoint, N, 0);

    const wind_angle = try get_row_major_data(alloc, fake_data, "wind_direction_10m", u9_to_f32, datapoint, N, 0);

    const temperature_2m = try get_row_major_data(alloc, fake_data, "temperature_2m", {}, datapoint, N, 0);

    const apparent_temperature = try get_row_major_data(alloc, fake_data, "apparent_temperature", {}, datapoint, N, 0);

    const MS = 1_000_000;
    comptime var scaling = 1.0;
    _ = wind_angle;

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});

    temperature(&img, scaling, temperature_2m);
    std.log.warn("temp {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/temperature-{d:.1}.ppm", .{scaling}));

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});
    rain(&img, scaling, precipitation, apparent_temperature);
    std.log.warn("rain {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/rain-{d:.1}.ppm", .{scaling}));

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});
    try wind_speed_color_map(&img, scaling, wind_speed);
    std.log.warn("wind {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/wind-{d:.1}.ppm", .{scaling}));

    scaling = 1.5;

    temperature(&img, scaling, temperature_2m);
    std.log.warn("temp {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/temperature-{d:.1}.ppm", .{scaling}));

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});
    rain(&img, scaling, precipitation, apparent_temperature);
    std.log.warn("rain {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/rain-{d:.1}.ppm", .{scaling}));

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});
    try wind_speed_color_map(&img, scaling, wind_speed);
    std.log.warn("wind {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/wind-{d:.1}.ppm", .{scaling}));
}

test "mtex" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    // interpolate to img size
    const img_size = 600;

    var img = try Image.init(alloc, img_size, img_size);
    const datapoints = 1;
    const N = 3 + 2 * 8;
    var benchmark_timer = std.time.Timer.start() catch unreachable;

    const fake_data = try create_random_data(alloc, N, datapoints);

    const datapoint = 0;
    const precipitation = try get_row_major_data(alloc, fake_data, "precipitation", null, datapoint, N, 0);

    const wind_speed = try get_row_major_data(alloc, fake_data, "wind_speed_10m", null, datapoint, N, 0);

    const wind_angle = try get_row_major_data(alloc, fake_data, "wind_direction_10m", u9_to_f32, datapoint, N, 0);

    const temperature_2m = try get_row_major_data(alloc, fake_data, "temperature_2m", {}, datapoint, N, 0);

    const apparent_temperature = try get_row_major_data(alloc, fake_data, "apparent_temperature", {}, datapoint, N, 0);

    _ = .{
        apparent_temperature, wind_speed, precipitation, wind_angle,
    };
    const MS = 1_000_000;
    comptime var scaling = 1.0;
    scaling = 1.1;

    std.log.warn("time init {} ms", .{benchmark_timer.lap() / MS});
    try render_tile_mt(alloc, &img, temperature, .{
        &img,
        scaling,
        temperature_2m,
    });
    std.log.warn("temp {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/temperaturemt-{d:.1}.ppm", .{scaling}));
    try render_tile_mt(alloc, &img, rain, .{
        &img,
        scaling,
        precipitation,
        temperature_2m,
    });
    std.log.warn("temp {} ms", .{benchmark_timer.lap() / MS});
    try img.write_ppm_to_file(std.fmt.comptimePrint("test/rain-{d:.1}.ppm", .{scaling}));
}
