# Contributing

Thanks for your interest in contributing!

## Prerequisites
- [Zig](https://ziglang.org/download/) 0.14.0+
- `git`

## Build & Test
```bash
git clone https://github.com/SMC17/cfr-solver-zig
cd cfr-solver-zig
zig build         # build
zig build test    # run test suite
```

## Submitting Changes
1. Fork the repo and create a feature branch
2. Make your changes with tests
3. Run `zig build test` — all tests must pass
4. Open a pull request with a clear description

## Issues
Use GitHub Issues to report bugs or request features.
Label appropriately: `bug`, `enhancement`, `documentation`.

## Code Style
- Follow Zig style guidelines
- Prefer comptime over runtime where possible
- Zero-allocation hot paths where feasible
- All public APIs need doc comments

## License
Apache 2.0 — see [LICENSE](LICENSE).
