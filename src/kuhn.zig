//! Kuhn poker vanilla CFR — converges to the Lean-certified game value.
//!
//! The formal anchor (aristotle-toolkit, Poker_KuhnTwoSided.lean, project a52066c0):
//!   kuhnT1_value        : valueQ eqP1Q kuhnT1 = -1/18   (native_decide, exact ℚ)
//!   kuhnT1_certified    : certifyEpsNashIS 6 eqP1Q kuhnT1 0
//!   kuhnT1_p1_cannot_improve : lifted to ℝ — no behavioral deviation improves.
//! Manifest keys: kuhnT1_value / kuhnT1_certified (axiom_closure: native) in
//! aristotle-pipeline/signals/proof_manifest_v3.json.
//!
//! CFR here is the numerical side of the bridge: the solver must converge to
//! the value the kernel certified. A drift from -1/18 is a bug in THIS code,
//! never in the target — that is what having a proved constant buys.

const std = @import("std");
const gate = @import("main.zig");

pub const PASS: usize = 0;
pub const BET: usize = 1;

const Infoset = struct {
    regret_sum: [2]f64 = .{ 0, 0 },
    strategy_sum: [2]f64 = .{ 0, 0 },

    fn strategy(self: *Infoset, reach_weight: f64) [2]f64 {
        var s: [2]f64 = .{ @max(0.0, self.regret_sum[0]), @max(0.0, self.regret_sum[1]) };
        const total = s[0] + s[1];
        if (total > 0) {
            s[0] /= total;
            s[1] /= total;
        } else {
            s = .{ 0.5, 0.5 };
        }
        self.strategy_sum[0] += reach_weight * s[0];
        self.strategy_sum[1] += reach_weight * s[1];
        return s;
    }

    fn average(self: *const Infoset) [2]f64 {
        const total = self.strategy_sum[0] + self.strategy_sum[1];
        if (total > 0)
            return .{ self.strategy_sum[0] / total, self.strategy_sum[1] / total };
        return .{ 0.5, 0.5 };
    }
};

/// 12 infosets: card (0..2 = J,Q,K) × history in {"", "p", "b", "pb"}.
pub const Trainer = struct {
    isets: [12]Infoset = .{Infoset{}} ** 12,

    fn key(card: u8, history: []const u8) usize {
        const h: usize = if (history.len == 0) 0
        else if (history.len == 1 and history[0] == 'p') 1
        else if (history.len == 1) 2
        else 3; // "pb"
        return @as(usize, card) * 4 + h;
    }

    /// Returns utility for the player to act, standard Kuhn CFR recursion.
    fn cfr(self: *Trainer, cards: [2]u8, history: []const u8, p0: f64, p1: f64, buf: []u8) f64 {
        const plays = history.len;
        const player: usize = plays % 2;

        if (plays > 1) {
            const higher = cards[player] > cards[1 - player];
            if (history[plays - 1] == 'p') {
                if (std.mem.eql(u8, history, "pp"))
                    return if (higher) 1.0 else -1.0; // showdown, antes only
                return 1.0; // opponent folded facing a bet
            }
            if (std.mem.endsWith(u8, history, "bb"))
                return if (higher) 2.0 else -2.0; // called bet showdown
        }

        const k = key(cards[player], history);
        const reach_w = if (player == 0) p0 else p1;
        const strat = self.isets[k].strategy(reach_w);

        var util: [2]f64 = .{ 0, 0 };
        var node_util: f64 = 0;
        for (0..2) |a| {
            @memcpy(buf[0..plays], history);
            buf[plays] = if (a == PASS) 'p' else 'b';
            const next = buf[0 .. plays + 1];
            util[a] = if (player == 0)
                -self.cfr(cards, next, p0 * strat[a], p1, buf[plays + 1 ..])
            else
                -self.cfr(cards, next, p0, p1 * strat[a], buf[plays + 1 ..]);
            node_util += strat[a] * util[a];
        }

        const opp_reach = if (player == 0) p1 else p0;
        for (0..2) |a| {
            self.isets[k].regret_sum[a] += opp_reach * (util[a] - node_util);
        }
        return node_util;
    }

    /// Train over all 6 deals per iteration (deterministic full enumeration).
    /// Returns the average game value for Player 1 — the quantity the Lean
    /// kernel certified to be exactly -1/18 at equilibrium.
    pub fn train(self: *Trainer, iterations: usize) f64 {
        const deals = [6][2]u8{
            .{ 0, 1 }, .{ 0, 2 }, .{ 1, 0 }, .{ 1, 2 }, .{ 2, 0 }, .{ 2, 1 },
        };
        var total: f64 = 0;
        var buf: [8]u8 = undefined;
        for (0..iterations) |_| {
            for (deals) |d| {
                total += self.cfr(d, "", 1.0, 1.0, &buf);
            }
        }
        return total / (6.0 * @as(f64, @floatFromInt(iterations)));
    }
};

/// The kernel-certified Kuhn value for Player 1 (kuhnT1_value, exact -1/18).
pub const certified_value_p1: f64 = -1.0 / 18.0;

test "CFR converges to the Lean-certified Kuhn value -1/18" {
    // Gate: the convergence-rate theorem is what licenses trusting T iterations.
    _ = gate.Gate(.cfr_convergence_rate){};
    var t = Trainer{};
    const v = t.train(20_000);
    try std.testing.expectApproxEqAbs(certified_value_p1, v, 0.005);
}

test "average strategy properties: bluff ratio alpha in [0,1/3], K always calls" {
    var t = Trainer{};
    _ = t.train(20_000);
    // Kuhn equilibria: P1 bets J (bluffs) with alpha in [0,1/3]; with K bets 3*alpha.
    const j_open = t.isets[Trainer.key(0, "")].average();
    const alpha = j_open[BET];
    try std.testing.expect(alpha >= -0.02 and alpha <= 1.0 / 3.0 + 0.02);
    // P2 with K facing a bet always calls.
    const k_facing_bet = t.isets[Trainer.key(2, "b")].average();
    try std.testing.expect(k_facing_bet[BET] > 0.97);
}

test "manifest cross-check: kuhnT1_value proved with native closure" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    // Tests have no environ handle in 0.16; same fallback the tree uses elsewhere.
    const path = "/home/user/aristotle-pipeline/signals/proof_manifest_v3.json";
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch
        return error.SkipZigTest; // machine without the pipeline: skip, don't fail
    defer allocator.free(bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    const keys = parsed.value.object.get("keys").?.object;
    for ([_][]const u8{ "kuhnT1_value", "kuhnT1_certified", "kuhnT1_exploit_zero" }) |k| {
        const entry = keys.get(k) orelse return error.MissingCertifiedKey;
        try std.testing.expect(entry.object.get("proved").?.bool);
        const closure = entry.object.get("axiom_closure").?.string;
        try std.testing.expect(std.mem.eql(u8, closure, "native") or
            std.mem.eql(u8, closure, "clean"));
    }
}
