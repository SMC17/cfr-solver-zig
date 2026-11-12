#!/usr/bin/env python3
"""Evaluate the actual average policy and enumerate all pure best responses.

Three cards, six equiprobable deals, ante one, bet one. This finite-game check
is independent of the trainer's regret recursion and trajectory-value counter.
"""
from fractions import Fraction as Q
import hashlib
import itertools
import json
import math
from pathlib import Path
import subprocess
import sys


def require(condition, detail):
    if not condition:
        raise AssertionError(detail)


def value(first, second):
    total = 0
    for a, b in itertools.permutations(range(3), 2):
        sign = 1 if a > b else -1
        opening_bet = first[4 * a][1]
        reply_call = second[4 * b + 2][1]
        after_check_bet = second[4 * b + 1][1]
        delayed_call = first[4 * a + 3][1]
        bet_branch = (1 - reply_call) + reply_call * 2 * sign
        check_branch = ((1 - after_check_bet) * sign +
                        after_check_bet * (-(1 - delayed_call) + delayed_call * 2 * sign))
        total += opening_bet * bet_branch + (1 - opening_bet) * check_branch
    return total / 6


def pure(player, bits):
    policy = [[Q(1), Q(0)] for _ in range(12)]
    histories = (0, 3) if player == 0 else (1, 2)
    for (card, history), action in zip(itertools.product(range(3), histories), bits):
        policy[4 * card + history] = [Q(1 - action), Q(action)]
    return policy


def responses(first, second):
    bits = list(itertools.product((0, 1), repeat=6))
    return (max(value(pure(0, b), second) for b in bits),
            min(value(first, pure(1, b)) for b in bits))


def reference():
    policy = [[Q(1), Q(0)] for _ in range(12)]
    for card, history, bet in [
        (0, 0, Q(1, 3)), (1, 0, Q(0)), (2, 0, Q(1)),
        (0, 3, Q(0)), (1, 3, Q(2, 3)), (2, 3, Q(1)),
        (0, 1, Q(1, 3)), (1, 1, Q(0)), (2, 1, Q(1)),
        (0, 2, Q(0)), (1, 2, Q(1, 3)), (2, 2, Q(1)),
    ]:
        policy[4 * card + history] = [1 - bet, bet]
    expected = Q(-1, 18)
    require(value(policy, policy) == expected, "Exact reference value")
    require(responses(policy, policy) == (expected, expected), "Exact reference best responses")
    # Independent terminal-payoff anchors catch sign/stake mistakes in the oracle.
    check = pure(0, (0,) * 6)
    check_second = pure(1, (0,) * 6)
    bet = pure(0, (1,) * 6)
    call = pure(1, (1,) * 6)
    require(value(check, check_second) == 0, "All-check showdown")
    require(value(bet, check_second) == 1, "Bet/fold payoff")
    require(value(check, call) == -1, "Check/bet/fold payoff")
    require(value(bet, call) == 0, "Bet/call showdown")
    return expected


def verify(binary):
    expected = reference()
    run = subprocess.run([str(binary.resolve(strict=True))], capture_output=True, timeout=30)
    require(run.returncode == 0 and not run.stderr, (run.returncode, run.stderr))
    result = json.loads(run.stdout)
    require(result["schema"] == 1 and result["game"] == "kuhn-ante1-bet1", result)
    require(result["history_ids"] == ["", "p", "b", "pb"], "History mapping")
    require(result["iterations"] == 20_000, "Fixed training task")
    policy = result["policy"]
    require(len(policy) == 12, "Twelve information sets")
    for row in policy:
        require(len(row) == 2 and all(math.isfinite(p) and 0 <= p <= 1 for p in row), row)
        require(abs(sum(row) - 1) < 1e-9, row)
    actual = value(policy, policy)
    first_br, second_br = responses(policy, policy)
    nash_conv = first_br - second_br
    require(math.isfinite(actual) and abs(actual - float(expected)) < 0.005, actual)
    require(0 <= nash_conv < 0.01, nash_conv)
    print(json.dumps({"status": "PASS", "game": result["game"], "iterations": 20_000,
                      "exact_reference": str(expected), "pure_responses_per_player": 64,
                      "average_policy_value": actual,
                      "player_one_best_response_value": first_br,
                      "player_one_value_against_player_two_best_response": second_br,
                      "nash_conv": nash_conv, "exploitability_half_nash_conv": nash_conv / 2,
                      "policy_output_sha256": hashlib.sha256(run.stdout).hexdigest(),
                      "scope": "Finite Kuhn policy evaluation; no Lean replay, general-game or real-money claim"}, indent=2))


if __name__ == "__main__":
    if len(sys.argv) > 2:
        raise SystemExit("Usage: python3 scripts/verify_kuhn.py [kuhn-task-binary]")
    verify(Path(sys.argv[1] if len(sys.argv) == 2 else "zig-out/bin/kuhn-task"))
