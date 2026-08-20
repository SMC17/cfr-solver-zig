# cfr-solver-zig status

Last touched: 2026-08-20
Last green: 2026-08-20 (`zig build test --summary all` — 7/7, Zig 0.16.0)

## Verification
- Proof level: `unit-tested` (7/7 tests pass on Zig 0.16.0)
- Primary gate: `zig build test --summary all`
- `Solver.iterate()` (after #3) calls `kuhn.Trainer.train(n)` then increments
  `iterations`. It is not a general-game CFR engine. Kuhn `Trainer` is the
  tested object (`zig build test --summary all` → 7/7).
