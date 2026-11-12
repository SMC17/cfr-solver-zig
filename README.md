# cfr-solver-zig

A private, Apache-2.0 research prototype for a fixed three-card Kuhn game.
The trainer enumerates all six deals. It is not a general extensive-game solver.

## One task

With Zig 0.16.0 and Python 3.12+:

```sh
zig build test -Doptimize=ReleaseSafe --summary all
zig build -Doptimize=ReleaseSafe
python3 scripts/verify_kuhn.py
```

The executable trains 20,000 iterations and exports the average policy as JSON.
Python evaluates that policy from terminal payoffs and enumerates all 64 pure
responses for each player. It does not reuse the trainer's regret recursion or
mistake its running trajectory value for the final policy's expected value.

The exact rational reference has value **-1/18**, agreeing with the standard
[Kuhn-game teaching result](https://www.cs.cmu.edu/afs/cs/academic/class/15780-s13/www/lec/ganzfried_gt.pdf).
The verifier independently checks its equilibrium value and both best responses
using fractions, plus terminal-payoff anchors. The trained policy must have
value error below 0.005 and NashConv below 0.01 on this fixed task. NashConv is
the sum of the two unilateral best-response gains; reported exploitability is
half that sum. These are game-payoff units, not trading or casino returns.

A measured run gives average-policy value about -0.055665 and exploitability
about 0.001430. Recompute with the command above; no speed measurement is claimed.

## State and proof boundaries

`Solver.iterate()` now retains its Kuhn trainer across calls instead of starting
from scratch and discarding the policy. A continuation regression requires
segmented and uninterrupted training to retain identical state.

The former claim catalog returned `proven` unconditionally. It now reports
`asserted`. No Lean kernel is run by this package. An optional local
`proof_manifest.json` metadata check skips when that file is absent; reading
metadata would still not replay a proof. Historical external proof references
remain in source comments for provenance, not as current validation.

`exploitabilityBound()` and `currentEpsilonBound()` evaluate an algebraic
expression. They do not measure the exported policy or establish that theorem
assumptions apply. Use the finite-game verifier for this task's measured scope.

## Keepable source and executable

```sh
python3 tools/selfserve.py selfserve.json --repo . --out /tmp/kuhn-selfserve
```

The shared recipe retains committed source, executable, command logs, exact
revision and checksums. Push/PR/manual/monthly workflow configuration and an
intentional preview-tag gate reuse the existing maintenance path. Private
visibility is preserved. Hosted configuration alone is not a passing run.
