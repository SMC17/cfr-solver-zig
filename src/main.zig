//! cfr-solver-zig — a bounded Kuhn-game research prototype.
//! Claim gates below are catalog assertions, not a Lean-kernel replay.

const std = @import("std");

// --------------------------------------------------------------------------
// Inline the proof gate — proof-gate-zig as a local copy for now
// (will become a proper dependency once published to pkg.ziglang.org)
// --------------------------------------------------------------------------

pub const ProofStatus = enum { asserted, proven, unproven, refuted };

pub const Claim = enum {
    cfr_convergence_rate,
    cfr_plus_potential,
    mccfr_unbiased,
    akq_exploitability_zero,
    hunl_push_fold_nash,
    cfr_exploitability_bound,
    minimax_theorem,
    nash_exists_zerosum,
    kuhn_poker_value,
    gto_guarantees_nash_payoff,
    range_advantage_ev,
    icm_concavity,
    gamblers_ruin,
};

fn claimStatus(c: Claim) ProofStatus {
    return switch (c) {
        .cfr_convergence_rate, .cfr_plus_potential, .mccfr_unbiased,
        .akq_exploitability_zero, .hunl_push_fold_nash, .cfr_exploitability_bound,
        .minimax_theorem, .nash_exists_zerosum, .kuhn_poker_value,
        .gto_guarantees_nash_payoff, .range_advantage_ev, .icm_concavity,
        .gamblers_ruin => .asserted,
    };
}

pub fn Gate(comptime claim: Claim) type {
    comptime {
        return switch (claimStatus(claim)) {
            .asserted => struct { pub const proof_status = ProofStatus.asserted; },
            .proven => struct { pub const proof_status = ProofStatus.proven; },
            .unproven => @compileError("Gate: " ++ @tagName(claim) ++ " not proven"),
            .refuted => @compileError("Gate: " ++ @tagName(claim) ++ " FORMALLY REFUTED"),
        };
    }
}

// --------------------------------------------------------------------------
// CFR Core
// --------------------------------------------------------------------------

pub const Action = enum(u2) { fold, call, raise };
pub const NUM_ACTIONS: usize = 3;

pub const InformationSet = struct {
    key: u64,
    regret_sum: [NUM_ACTIONS]f64 = .{0} ** NUM_ACTIONS,
    strategy_sum: [NUM_ACTIONS]f64 = .{0} ** NUM_ACTIONS,

    pub fn strategy(self: *const InformationSet) [NUM_ACTIONS]f64 {
        var s = self.regret_sum;
        var sum: f64 = 0.0;
        for (&s) |*r| {
            if (r.* < 0.0) r.* = 0.0;
            sum += r.*;
        }
        if (sum > 0.0) {
            for (&s) |*r| r.* /= sum;
        } else {
            for (&s) |*r| r.* = 1.0 / NUM_ACTIONS;
        }
        return s;
    }

    pub fn averageStrategy(self: *const InformationSet) [NUM_ACTIONS]f64 {
        var s = self.strategy_sum;
        var sum: f64 = 0.0;
        for (s) |v| sum += v;
        if (sum > 0.0) {
            for (&s) |*v| v.* /= sum;
        } else {
            for (&s) |*v| v.* = 1.0 / NUM_ACTIONS;
        }
        return s;
    }
};

/// CFR+ regret update — cfr_plus_potential gate ensures non-negative regret floor.
pub fn updateRegretCFRPlus(
    comptime _: Gate(.cfr_plus_potential),
    iset: *InformationSet,
    action_values: [NUM_ACTIONS]f64,
    node_value: f64,
    reach_prob: f64,
) void {
    _ = reach_prob;
    for (0..NUM_ACTIONS) |a| {
        const regret = action_values[a] - node_value;
        iset.regret_sum[a] = @max(0.0, iset.regret_sum[a] + regret);
    }
}

/// Evaluate the algebraic expression 2U/sqrt(T).
/// This does not measure exploitability or verify that theorem assumptions hold.
pub fn exploitabilityBound(
    comptime _: Gate(.cfr_convergence_rate),
    utility_bound: f64,
    iterations: usize,
) f64 {
    return 2.0 * utility_bound / @sqrt(@as(f64, @floatFromInt(iterations)));
}

/// Wrapper around the specific Kuhn trainer; not a general-game solver.
pub fn Solver(comptime utility_bound: f64) type {
    // Preserve the legacy gate API while reporting its actual asserted status.
    const _convergence_gate = Gate(.cfr_convergence_rate){};
    _ = _convergence_gate;

    return struct {
        isets: std.AutoHashMap(u64, InformationSet),
        iterations: usize = 0,
        allocator: std.mem.Allocator,
        kuhn_trainer: kuhn.Trainer = .{},

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .isets = std.AutoHashMap(u64, InformationSet).init(allocator), .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            self.isets.deinit();
        }

        /// Algebraic expression only; use the separate finite-game best-response check.
        pub fn currentEpsilonBound(self: *const Self) f64 {
            if (self.iterations == 0) return utility_bound * 2.0;
            return exploitabilityBound(.{}, utility_bound, self.iterations);
        }

        /// Continue the same Kuhn trainer across calls. The average policy is
        /// retained in kuhn_trainer; no general-game exploitability is asserted.
        pub fn iterate(self: *Self, n: usize) !void {
            if (n == 0) return;
            _ = self.kuhn_trainer.train(n);
            self.iterations += n;
        }
    };
}

test "exploitability bound decreases" {
    const bound_100 = exploitabilityBound(.{}, 1.0, 100);
    const bound_10000 = exploitabilityBound(.{}, 1.0, 10000);
    try std.testing.expect(bound_10000 < bound_100);
    try std.testing.expectApproxEqAbs(0.2, bound_100, 1e-10);
    try std.testing.expectApproxEqAbs(0.02, bound_10000, 1e-10);
}

test "CFR+ regret update stays non-negative" {
    var iset = InformationSet{ .key = 42 };
    // Negative regret should be floored to 0 by CFR+
    const values = [NUM_ACTIONS]f64{ -1.0, -2.0, -3.0 };
    updateRegretCFRPlus(.{}, &iset, values, 0.0, 1.0);
    for (iset.regret_sum) |r| {
        try std.testing.expect(r >= 0.0);
    }
}

test "Solver evaluates its declared algebraic expression" {
    const MySolver = Solver(1.0);
    var s = MySolver.init(std.testing.allocator);
    defer s.deinit();
    try s.iterate(1000);
    const eps = s.currentEpsilonBound();
    try std.testing.expect(eps <= 2.0 / @sqrt(1000.0) + 1e-9);
}

test "claim gates report assertions rather than kernel verification" {
    try std.testing.expectEqual(ProofStatus.asserted, Gate(.cfr_convergence_rate).proof_status);
}

test "segmented training retains the same policy as uninterrupted training" {
    var segmented = Solver(2.0).init(std.testing.allocator);
    defer segmented.deinit();
    var whole = kuhn.Trainer{};
    _ = whole.train(1000);
    try segmented.iterate(400);
    try segmented.iterate(600);
    try segmented.iterate(0);
    try std.testing.expectEqual(@as(usize, 1000), segmented.iterations);
    for (whole.isets, segmented.kuhn_trainer.isets) |expected, actual| {
        try std.testing.expectEqualSlices(f64, &expected.regret_sum, &actual.regret_sum);
        try std.testing.expectEqualSlices(f64, &expected.strategy_sum, &actual.strategy_sum);
    }
}

pub const kuhn = @import("kuhn.zig");

test {
    _ = kuhn;
}
