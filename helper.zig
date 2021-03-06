const std = @import("std");
const maxInt = std.math.maxInt;
const log = std.debug.warn;

const c = @import("c.zig");
const gw = c.gw;
const gmp = c.gmp;

const glue = @import("glue.zig");

pub fn create_gwhandle(ctx: *gw.gwhandle, threads: u8, k: u32, n: u32) void {
    gw.gwinit2(ctx, @sizeOf(gw.gwhandle), gw.GWNUM_VERSION);

    // features
    ctx.use_large_pages = 1;
    ctx.num_threads = threads;
    ctx.will_hyperthread = threads;
    ctx.bench_num_cores = threads;

    // safety
    //ctx.larger_fftlen_count = 0;
    //ctx.safety_margin = 0.3;
    // we do the careful squating explicitly
    //gw.gwset_square_carefully_count(ctx, 50);
    //ctx.use_irrational_general_mod = 1;
    ctx.sum_inputs_checking = 1;
    ctx.will_error_check = 1;

    const _na = gw.gwsetup(ctx, @intToFloat(f64, k), 2, n, -1);
}

pub fn benchmark_threads(u0_gmp: gmp.mpz_t, k: u32, n: u32) u8 {
    const max_threads: u32 = 8;
    const iterations: u32 = 1000;

    var best_speed: u64 = 0xffffffffffffffff;
    var best_threadcount: u8 = 0;

    var warmup: bool = true;

    var i: u8 = 1;
    while (i <= max_threads) {
        var ctx: gw.gwhandle = undefined;
        create_gwhandle(&ctx, i, k, n);
        var u: gw.gwnum = gw.gwalloc(&ctx);
        glue.gmp_to_gw(u0_gmp, u, &ctx);

        const start = std.time.milliTimestamp();
        gw.gwsetaddin(&ctx, -2);
        var j: u32 = 0;
        while (j < iterations) : (j += 1) {
            gw.gwsquare2(&ctx, u, u);
            gw.gwstartnextfft(&ctx, 1);
        }
        const delta = std.time.milliTimestamp() - start;
        // larger threadcount has to be at least 5% better
        if (@intToFloat(f64, delta) < (@intToFloat(f64, best_speed) * 0.95)) {
            best_speed = delta;
            best_threadcount = i;
        }
        if (warmup) {
            warmup = false;
            continue;
        }
        log("threads {} took {}ms for {} iterations\n", .{ i, delta, iterations });
        i += 1;
    }
    log("using fastest threadcount {}\n", .{best_threadcount});
    return best_threadcount;
}

pub fn min(comptime T: type, a: T, b: T) T {
    return if (a <= b) a else b;
}

///
/// copied from official Zig docs
/// https://ziglang.org/documentation/master/#toc-Error-Union-Type
///
pub fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;
    for (buf) |ch| {
        const digit = charToDigit(ch);
        if (digit >= radix) {
            return error.InvalidChar;
        }
        // x *= radix
        if (@mulWithOverflow(u64, x, radix, &x)) {
            return error.Overflow;
        }
        // x += digit
        if (@addWithOverflow(u64, x, digit, &x)) {
            return error.Overflow;
        }
    }
    return x;
}

fn charToDigit(ch: u8) u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'A'...'Z' => ch - 'A' + 10,
        'a'...'z' => ch - 'a' + 10,
        else => maxInt(u8),
    };
}
