const std = @import("std");
const log = std.debug.warn;
const stdout = &std.io.getStdOut().outStream();
const assert = @import("std").debug.assert;
const fmt = @import("std").fmt;

const c = @import("c.zig");
const gw = c.gw;
const gmp = c.gmp;

const glue = @import("glue.zig");
const helper = @import("helper.zig");
const u_zero = @import("u_zero.zig");

pub fn full_fermat_run(k: u32, b: u32, n: u32, c_: i32, threads_: u8) !bool {
    const PRP_BASE: usize = 2;
    var N: gmp.mpz_t = u_zero.calculate_N(k, n);

    const n_digits = gmp.mpz_sizeinbase(&N, 10);
    log("Fermat {}-PRP testing: {}*{}^{}{} [{} digits] on {} threads\n", .{ PRP_BASE, k, b, n, c_, n_digits, threads_ });

    var N_min_1: gmp.mpz_t = undefined;
    gmp.mpz_init_set(&N_min_1, &N);
    gmp.mpz_sub_ui(&N_min_1, &N_min_1, 1);
    const N_min_1_bits = gmp.mpz_sizeinbase(&N_min_1, 2);

    var gmp_one: gmp.mpz_t = undefined;
    gmp.mpz_init_set_ui(&gmp_one, 1);

    var gmp_base: gmp.mpz_t = undefined;
    gmp.mpz_init_set_ui(&gmp_base, PRP_BASE);

    var ctx: gw.gwhandle = undefined;
    helper.create_gwhandle(&ctx, threads_, k, n);

    var buf: gw.gwnum = gw.gwalloc(&ctx);
    glue.gmp_to_gw(gmp_one, buf, &ctx);

    var gw_base: gw.gwnum = gw.gwalloc(&ctx);
    glue.gmp_to_gw(gmp_base, gw_base, &ctx);

    var gw_one: gw.gwnum = gw.gwalloc(&ctx);
    glue.gmp_to_gw(gmp_one, gw_one, &ctx);

    var i: usize = N_min_1_bits - 1;
    // we activate this with the setting of ctx.NORMNUM
    var near_fft = false;
    var errored = false;
    gw.gwsetmulbyconst(&ctx, PRP_BASE);
    ctx.NORMNUM = 0;
    while (i <= N_min_1_bits) : (_ = @subWithOverflow(usize, i, 1, &i)) {
        if (i == 1 and 1 == gw.gwequal(&ctx, buf, gw_one)) {
            log("!!! SANITY CHECK FAILED, PREMATURE PRP STATUS, THIS IS A BUG\n", .{});
        }
        // allow for 64 bit k to mangle the first bits
        // this if/else allows us to not check bits in most of the number
        const optimized_mult = i < N_min_1_bits - helper.min(usize, 64, N_min_1_bits) and N_min_1_bits >= 64;
        // first log2(k) bits _have_ to be handled here
        // FIXME: the optimized case does not work for small numbers, eg. 3*2^11-1
        if (!optimized_mult) {
            const bit_set = gmp.mpz_tstbit(&N_min_1, i) == 1;
            if (i < 50 or i > N_min_1_bits - 50) {
                gw.gwsquare2_carefully(&ctx, buf, buf);
            } else {
                gw.gwsquare2(&ctx, buf, buf);
            }
            if (bit_set) {
                gw.gwsmallmul(&ctx, PRP_BASE, buf);
            }
        } else {
            // here we assume all bits are set (b/c we have Riesel numbers, they have all 1's after a point)
            ctx.NORMNUM = 3;
            if (i == 0) {
                // turn off const multiplication for last bit, b/c it's 0 for some reason
                const bit_set = gmp.mpz_tstbit(&N_min_1, i) == 1;
                ctx.NORMNUM = 0;
            }
            if (i > 50 and i < N_min_1_bits - 50) {
                gw.gwstartnextfft(&ctx, 1);
            } else {
                gw.gwstartnextfft(&ctx, 0);
            }
            const careful = i < 50 or i > N_min_1_bits - 49;
            if (careful) {
                gw.gwsquare2_carefully(&ctx, buf, buf);
            } else {
                gw.gwsquare2(&ctx, buf, buf);
            }
        }

        // check if near fft limit
        if (gw.gwnear_fft_limit(&ctx, 0.5) != 0) {
            if (!near_fft) {
                log("WARNING: near FFT limit @ {}\n", .{i});
                near_fft = true;
            }
        }

        // error_check
        if (true) {
            if (gw.gw_test_illegal_sumout(&ctx) != 0) {
                errored = true;
                log("ERROR: illegal sumout @ {}\n", .{i});
            }
            if (gw.gw_test_mismatched_sums(&ctx) != 0) {
                errored = true;
                log("ERROR: mismatched sums @ {}\n", .{i});
            }
            if (gw.gw_get_maxerr(&ctx) >= 0.40) {
                errored = true;
                log("ERROR: maxerr > 0.4 @ {} = {}\n", .{ i, gw.gw_get_maxerr(&ctx) });
            }
        }
    }

    var is_prp = gw.gwequal(&ctx, buf, gw_one);
    if (is_prp == 1) {
        const maybe = "maybe";
        log("#> {}*{}^{}{} [{} digits] IS {}-PRP!\n", .{ k, b, n, c_, n_digits, PRP_BASE });
    } else {
        log("#> {}*{}^{}{} [{} digits] is not prime ({})\n", .{
            k,
            b,
            n,
            c_,
            n_digits,
            is_prp,
        });
    }
    return is_prp == 1;
}
