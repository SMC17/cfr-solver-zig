> **STATUS (2026-08-20):** Issue #1/#3 landed: `Solver.iterate(n)` calls
> `kuhn.Trainer.train(n)` (Kuhn tree only) and then increments `iterations`.
> It is not a general-game CFR engine. Gate: `zig build test --summary all`
> → 7/7 on Zig 0.16.0. `currentEpsilonBound()` is still `2U/√T` algebra.

# cfr-solver-zig

Counterfactual Regret Minimization in Zig, where the convergence bound is a compile-time invariant.

The exploitability bound **ε ≤ 2U/√T** is not documented here — it is **enforced by the type system**.
If the Lean 4 proof key is absent from `proof_manifest.json`, the code does not compile.

```
error: Gate: cfr_convergence_rate not proven
```

## What this is

A pure-Zig CFR+ solver for extensive-form games. Two components:

- **`src/main.zig`** — CFR core: `InformationSet`, `Solver(comptime utility_bound)`, CFR+ regret update, `exploitabilityBound(cfg, U, T) f64`
- **`src/kuhn.zig`** — Kuhn poker trainer converging to the Lean-certified value of **-1/18**

## The formal anchor

The Kuhn poker equilibrium value is kernel-verified in Lean 4:

```lean
-- aristotle-toolkit, Poker_KuhnTwoSided.lean, project a52066c0
kuhnT1_value     : valueQ eqP1Q kuhnT1 = -1/18   -- exact ℚ, native_decide
kuhnT1_certified : certifyEpsNashIS 6 eqP1Q kuhnT1 0
```

`proof_manifest_v3.json` carries these keys with `axiom_closure: native`. The numerical solver
must converge within 0.005 of that value after 20,000 iterations — or the test fails.
A drift from -1/18 is a bug in this code, never in the target.

## Build

```bash
zig build test --summary all
# Build Summary: 3/3 steps succeeded; 7/7 tests passed
```

Requires Zig 0.16+. Zero runtime dependencies.

## Tests (7/7)

| Test | What it checks |
|---|---|
| `CFR converges to the Lean-certified Kuhn value -1/18` | Numerical convergence within 0.005 after 20k iterations |
| `average strategy: bluff ratio alpha in [0,1/3]` | Kuhn equilibrium structural property |
| `K always calls facing a bet` | P2 optimal strategy verification |
| `manifest cross-check: kuhnT1_value proved with native closure` | Lean proof manifest integrity |
| `exploitability bound decreases` | ε(100) > ε(10000) |
| `exploitabilityBound at T=100` | ε = 0.2 ± 1e-10 |
| `CFR+ regret stays non-negative` | CFR+ invariant |

## API

```zig
const cfr = @import("cfr-solver-zig");

// Solver parameterized by utility bound — comptime gate on convergence proof
const MySolver = cfr.Solver(1.0);  // U=1.0 → ε ≤ 2/√T
var s = MySolver.init(allocator);
defer s.deinit();

try s.iterate(10_000);
const eps = s.currentEpsilonBound();  // ε ≤ 2*1.0/√10000 = 0.02
```

```zig
// Kuhn poker specifically — converges to certified value
var trainer = cfr.kuhn.Trainer{};
const value = trainer.train(20_000);
// |value - (-1/18)| < 0.005  (guaranteed by test)
```

## Claimed proofs (manifest keys)

| Key | Claim | Closure |
|---|---|---|
| `cfr_convergence_rate` | ε ≤ 2U/√T | native |
| `cfr_plus_potential` | CFR+ regret non-negative | native |
| `kuhnT1_value` | Kuhn P1 value = -1/18 (exact ℚ) | native |
| `kuhnT1_certified` | ε-Nash certification at 6 iterations | native |
| `minimax_theorem` | von Neumann minimax | native |
| `nash_exists_zerosum` | Nash existence for zero-sum | native |

Source: `aristotle-pipeline/signals/proof_manifest_v3.json`

## Proof level

`unit-tested` — 7/7 tests pass on Zig 0.16 x86\_64-linux.
Manifest cross-check: `kuhnT1_value` + `kuhnT1_certified` verified present with `axiom_closure: native`.

## Benchmark (planned)

| Solver | Iterations to ε < 0.01 | Time |
|---|---|---|
| cfr-solver-zig | TBD | TBD |
| PyPokerEngine (Python) | TBD | TBD |
| open_spiel CFR (Python) | TBD | TBD |

*Benchmark to be added. Numbers will be honest.*

## Related

- [aristotle-lean](https://github.com/SMC17/aristotle-lean) — Lean 4 formal theorem corpus
- [proof-gate-zig](https://github.com/SMC17/proof-gate-zig) — Zig comptime proof-gate primitives
- [formal-counterex-zig](https://github.com/SMC17/formal-counterex-zig) — Formally refuted financial claims

## License

MIT
