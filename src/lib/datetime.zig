const std = @import("std");

/// A simple struct to hold the broken-down date and time.
pub const DateTime = struct {
    year: i32,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
};

/// Convert a Unix timestamp (seconds since 1970-01-01 00:00:00 UTC) into year, month, day.
fn daysToYMD(days: i64) DateTime {
    // Based on Howard Hinnant's civil_from_days algorithm
    // const z = days + 719468;
    // const era = if (z >= 0) z / 146097 else (z - 146096) / 146097;
    // const doe = z - era * 146097;
    // const yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    // var y = yoe + era * 400;
    // const doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    // const mp = (5 * doy + 2) / 153;
    // const d = doy - (153 * mp + 2) / 5 + 1;
    // const m = mp + (if (mp < 10) 3 else -9);
    // y += if (m <= 2) 1 else 0;

    const z: i64 = days + 719468;
    const era = if (z >= 0) @divTrunc(z, 146097) else @divTrunc(z - 146096, 146097);
    const doe = z - era * 146097;
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    var y: i64 = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
    const mp = @divTrunc(5 * doy + 2, 153);
    const d = doy - @divTrunc(153 * mp + 2, 5) + 1;
    const m = if (mp < 10) mp + 3 else mp - 9;
    if (m <= 2) y += 1 else y += 0;

    return DateTime{
        .year = @as(i32, @intCast(y)),
        .month = @as(u8, @intCast(m)),
        .day = @as(u8, @intCast(d)),
        .hour = 0,
        .minute = 0,
        .second = 0,
    };
}

/// Convert a Unix epoch timestamp to a DateTime (UTC).
pub fn unixToDateTime(unix: i64) DateTime {
    // Compute days and leftover seconds, handling negative timestamps correctly
    const secsPerDay: i64 = 24 * 60 * 60;
    const days: i64 = if (unix >= 0) @divTrunc(unix, secsPerDay) else @divTrunc((unix - (secsPerDay - 1)), secsPerDay);
    var rem: i64 = unix - days * secsPerDay;
    if (rem < 0) rem += secsPerDay;

    // Break out hours, minutes, seconds

    const hour = @as(u8, @intCast(@divTrunc(rem, 3600)));
    rem = @mod(rem, 3600);
    const minute = @as(u8, @intCast(@divTrunc(rem, 60)));
    const second = @as(u8, @intCast(@mod(rem, 60)));

    // Get year/month/day
    var dt = daysToYMD(days);
    dt.hour = hour;
    dt.minute = minute;
    dt.second = second;
    return dt;
}

// Example usage: print the current time
test "main()" {
    const ts = @divTrunc(std.time.milliTimestamp(), 1000);
    const dt = unixToDateTime(ts);
    std.debug.print("UTC: {d}/{:0>2}/{:0>2} {:0>2}:{:0>2}:{:0>2}\n", .{ dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second });
}
