const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const root = @import("../root.zig");
const sqlite = @import("sqlite");
const osmr = @import("osmr");
const weatherapi = root.weather.weather;
const Conn = sqlite.Conn;
const PreparedStatement = sqlite.PreparedStatement;
const CollectOne = sqlite.CollectOne;
const void_ptr = sqlite.void_ptr;
const no_op = sqlite.no_op;
const no_op2 = sqlite.no_op3;

const UnixEpochSeconds = i64;
const WeatherSQL = struct {
    lat: f32,
    lon: f32,
    start_time: UnixEpochSeconds,
    end_time: UnixEpochSeconds,
    blob: []const u8,
    const TABLE_NAME = sqlite.sql.type_name_as_str(@This());
    const FIELD_COUNT = @typeInfo(@This()).@"struct".fields.len;
};

const MaptileSQL = struct {
    x: u32,
    y: u32,
    z: u32,
    blob: []const u8,
    const TABLE_NAME = sqlite.sql.type_name_as_str(@This());
    const FIELD_COUNT = @typeInfo(@This()).@"struct".fields.len;
};

pub const Cache = @This();

const UsizeCountOf = CollectOne(struct { usize });
pub const ResultWeather = CollectOne(WeatherSQL);
pub const ResultMaptile = CollectOne(MaptileSQL);

const WeatherStatements = struct {
    stmt_insert: PreparedStatement,
    stmt_delete_all: PreparedStatement,
    stmt_get_in_timerange: PreparedStatement,

    fn delete_all(self: *@This()) !void {
        try self.stmt_delete_all.exec(void, void_ptr, no_op2);
    }
    fn insert(self: *@This(), lat: f32, lon: f32, start_time: UnixEpochSeconds, end_time: UnixEpochSeconds, data: []const u8) !void {
        try self.stmt_insert.bind_f64(1, lat);
        try self.stmt_insert.bind_f64(2, lon);
        try self.stmt_insert.bind_i64(3, start_time);
        try self.stmt_insert.bind_i64(4, end_time);
        try self.stmt_insert.bind_text_u8(5, data);
        try self.stmt_insert.exec(void, void_ptr, no_op2);
    }
    fn get_in_timerange(self: *@This(), alloc: Allocator, time: UnixEpochSeconds) !ResultWeather {
        const Get = ResultWeather;
        var gw = Get{ .alloc = alloc };
        try self.stmt_get_in_timerange.bind_i64(1, time);
        try self.stmt_get_in_timerange.exec(ResultWeather, &gw, ResultWeather.collect);
        _ = try gw.result();
        return gw;
    }
};
const MaptileStatements = struct {
    stmt_insert: PreparedStatement,
    stmt_count_where_xyz: PreparedStatement,
    stmt_get_xyz: PreparedStatement,
    fn insert(self: *@This(), x: u32, y: u32, z: u32, data: []const u8) !void {
        try self.stmt_insert.bind_i32(1, @intCast(x));
        try self.stmt_insert.bind_i32(2, @intCast(y));
        try self.stmt_insert.bind_i32(3, @intCast(z));
        try self.stmt_insert.bind_text_u8(4, data);
        try self.stmt_insert.exec(void, void_ptr, no_op2);
    }

    fn count(self: *@This(), x: u32, y: u32, z: u32) !usize {
        var count_of = UsizeCountOf{ .alloc = undefined };
        try self.stmt_count_where_xyz.bind_i64(1, @intCast(x));
        try self.stmt_count_where_xyz.bind_i64(2, @intCast(y));
        try self.stmt_count_where_xyz.bind_i64(3, @intCast(z));
        try self.stmt_count_where_xyz.exec(UsizeCountOf, &count_of, UsizeCountOf.collect);
        return count_of.inner.?.@"0";
    }
    fn get(self: *@This(), alloc: Allocator, x: u32, y: u32, z: u32) !ResultMaptile {
        var gw = ResultMaptile{ .alloc = alloc };
        try self.stmt_get_xyz.bind_i64(1, x);
        try self.stmt_get_xyz.bind_i64(2, y);
        try self.stmt_get_xyz.bind_i64(3, z);
        try self.stmt_get_xyz.exec(ResultMaptile, &gw, ResultMaptile.collect);
        _ = try gw.result();
        return gw;
    }
};

db: Conn,
prng: std.Random.DefaultPrng,
maptile: MaptileStatements,
weather: WeatherStatements,

pub fn init(db_name: []const u8) !@This() {
    // NOTE: indices of ?NNN must be between ?1 and ?32766
    var buf: [4096]u8 = undefined;
    const use_cwd = true;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    var maptile: MaptileStatements = undefined;
    var weather: WeatherStatements = undefined;

    const exe_dir = if (use_cwd)
        try std.fs.cwd().realpathAlloc(alloc, "./")
    else
        try std.fs.selfExeDirPathAlloc(alloc);

    const db_path = try std.fmt.allocPrintZ(alloc, "{s}/{s}.db", .{ exe_dir, db_name });
    std.debug.print("cache path is {s}\n", .{db_path});
    var db = try Conn.init(db_path);
    const create_table_weather_data_sql = comptime sqlite.sql.simple_table_from_struct(WeatherSQL, WeatherSQL.TABLE_NAME);
    try db.execute(create_table_weather_data_sql, void, void_ptr, no_op);

    const create_table_maptile_sql = comptime sqlite.sql.simple_table_from_struct(MaptileSQL, MaptileSQL.TABLE_NAME);
    try db.execute(create_table_maptile_sql, void, void_ptr, no_op);
    maptile.stmt_insert = try db.prepare_statement(
        comptime sqlite.sql.insert(
            MaptileSQL.TABLE_NAME,
            sqlite.sql.list_of_question_marks(MaptileSQL.FIELD_COUNT),
        ),
    );

    maptile.stmt_count_where_xyz = try db.prepare_statement(
        std.fmt.comptimePrint(
            \\SELECT COUNT(*) as Entries
            \\FROM
            \\{s}
            \\where x = ? and y = ? and z = ?;
        , .{MaptileSQL.TABLE_NAME}),
    );

    maptile.stmt_get_xyz = try db.prepare_statement(
        std.fmt.comptimePrint(
            \\SELECT *
            \\FROM
            \\{s}
            \\where x = ? and y = ? and z = ? LIMIT 1;
        , .{MaptileSQL.TABLE_NAME}),
    );

    weather.stmt_insert = try db.prepare_statement(
        comptime sqlite.sql.insert(
            WeatherSQL.TABLE_NAME,
            sqlite.sql.list_of_question_marks(WeatherSQL.FIELD_COUNT),
        ),
    );

    weather.stmt_delete_all = try db.prepare_statement(
        std.fmt.comptimePrint(
            \\ DELETE FROM {s}
        , .{WeatherSQL.TABLE_NAME}),
    );

    weather.stmt_get_in_timerange = try db.prepare_statement(
        std.fmt.comptimePrint(
            \\SELECT *
            \\FROM
            \\{s}
            \\WHERE ? between start_time AND end_time;
        , .{WeatherSQL.TABLE_NAME}),
    );

    return @This(){
        .db = db,
        .weather = weather,
        .maptile = maptile,
        .prng = prng,
    };
}
pub fn deinit(self: *@This()) void {
    inline for (@typeInfo(MaptileStatements).@"struct".fields) |f| {
        const statement_field = &@field(self.maptile, f.name);
        statement_field.deinit();
    }
    inline for (@typeInfo(WeatherStatements).@"struct".fields) |f| {
        const statement_field = &@field(self.weather, f.name);
        statement_field.deinit();
    }
    self.db.deinit();
}

const api_key: []const u8 = &get_api_key();
pub fn get_or_fetch_maptile(self: *@This(), alloc: Allocator, x: u32, y: u32, z: u32) !ResultMaptile {
    if (try self.maptile.count(x, y, z) == 0) {
        // std.log.warn("try fetch x: {}, y: {}, z: {} from maptiler", .{ x, y, z });
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const dat = try osmr.maptiler.downloadTile(arena.allocator(), x, y, z, api_key);
        try self.maptile.insert(x, y, z, dat);
        return try self.maptile.get(alloc, x, y, z);
    } else {
        // std.log.warn("x: {}, y: {}, z: {} from cache", .{ x, y, z });
        return try self.maptile.get(alloc, x, y, z);
    }
}

pub fn get_api_key() [20]u8 {
    comptime {
        var buffer: [20]u8 = undefined;
        const Env = osmr.maptiler.Env;
        const file_content = @embedFile(".env");
        const key = Env.parse_key("maptiler_api_key", file_content) catch @compileError("dotenv does not have this key");
        std.mem.copyForwards(u8, &buffer, key.?);
        return buffer;
    }
}
pub const ManagedMeteoJsonResult = struct {
    arena: std.heap.ArenaAllocator,
    val: []const MeteoJsonResult,
    pub fn deinit(self: *const @This()) void {
        self.arena.deinit();
    }
};
const mserde = struct {
    fn deserialize(mgpa: Allocator, blob: []const u8) !ManagedMeteoJsonResult {
        var marena = std.heap.ArenaAllocator.init(mgpa);
        var reader = std.io.fixedBufferStream(blob);
        var de = serde.deserializer(.little, .bit, reader.reader());
        const de_res = try de.deserialize(
            []const MeteoJsonResult,
            marena.allocator(),
        );
        return ManagedMeteoJsonResult{
            .arena = marena,
            .val = de_res,
        };
    }
    fn serialize(malloc: Allocator, value: []const MeteoJsonResult) ![]const u8 {
        var serialized_data = std.ArrayList(u8).init(malloc);
        const writer = serialized_data.writer();
        var ser = serde.serializer(.little, .bit, writer);
        try ser.serialize([]const MeteoJsonResult, value);
        return serialized_data.items;
    }
};
pub const MeteoJsonResult = weatherapi.Minutes15Raw.MeteoJsonResult;
//TODO: permit a little bit of diffrence in lat lon coordinates to not refetch basically same location
pub const WEATHER_DATAPOINTS = 12 * 4;
pub fn get_or_fetch_weather_data(
    self: *@This(),
    gpa: Allocator,
    lat: f32,
    lon: f32,
    z: u32,
    order: usize,
) !ManagedMeteoJsonResult {
    const unix_time_now = std.time.timestamp();
    const unix_time_in_6h = unix_time_now + 6 * 3600;
    const datapoints = WEATHER_DATAPOINTS;
    var local_arena = std.heap.ArenaAllocator.init(gpa);
    defer local_arena.deinit();
    const trash_alloc = local_arena.allocator();

    const query = try self.weather.get_in_timerange(trash_alloc, unix_time_in_6h);
    if (query.inner) |q| {
        std.log.warn("weather from cache", .{});
        return try mserde.deserialize(gpa, q.blob);
    } else {
        // fetching the points (either from meteo or cached from database, write this fn in the Cache/DB, fetch for 12h refetch after 6h)
        try self.weather.delete_all();
        std.log.warn("refetch weather", .{});
        // fake data
        // const http_result = try @import("weather").render.create_random_data(trash_alloc, 1 + (1 + order) * 2, datapoints);
        // _ = z;
        // const start_time = unix_time_now;
        // const end_time = unix_time_now + 12 * 3600;
        // end

        // realdata
        const llarr = try weatherapi.forecast_points_row_major_order(trash_alloc, order, lat, lon, z);
        const http_result = try weatherapi.Minutes15Raw.fetch_multiple(trash_alloc, datapoints, llarr.lat, llarr.lon, 1024 * 1024 * 250);
        const first_time = http_result[0].minutely_15.time;
        const start_time = first_time[0];
        const end_time = first_time[first_time.len - 1];
        // end

        const serdat = try mserde.serialize(trash_alloc, http_result);
        try self.weather.insert(lat, lon, start_time, end_time, serdat);
        return try mserde.deserialize(gpa, serdat);
    }
}
test "serde" {
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const wdata = try root.weather.render.create_random_data(alloc, 19, 12 * 4);
    const dat = try mserde.serialize(alloc, wdata);
    const x = try mserde.deserialize(alloc, dat);

    std.log.debug("{any}", .{x.val});
}

test "db delete weather cache" {
    // if (true) return;
    var db = try Cache.init("cache");
    defer db.deinit();
    try db.weather.delete_all();
}
test "test db" {
    if (true) return;
    const gpa = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    var db = try Cache.init("testdb1");
    defer db.deinit();
    if (try db.maptile.count(0, 0, 0) == 0) {
        try db.maptile.insert(0, 0, 0, "hello");
    }
    var maptile = try db.maptile.get(alloc, 0, 0, 0);
    defer maptile.deinit();

    try expect(std.mem.eql(u8, maptile.inner.?.blob, "hello"));

    try db.weather.insert(5, 10, 100, 1000, "100-through-1000");
    const time_range_result = try db.weather.get_in_timerange(alloc, 300);
    std.log.warn("{any}", .{time_range_result.inner.?});
    const out_of_range_result = try db.weather.get_in_timerange(alloc, 1001);
    assert(out_of_range_result.inner == null);

    const res = try db.get_or_fetch_weather_data(gpa, 52, 12, 22, 0);
    std.log.warn("res: {any}", .{res.val});
    defer res.deinit();
}

const serde = @import("serde");
