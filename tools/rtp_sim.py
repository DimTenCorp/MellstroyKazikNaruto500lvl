#!/usr/bin/env python3
"""RTP simulator for the 3x5 slot machine (mirrors scripts/slot_data.gd).

Dev tool: run `python3 tools/rtp_sim.py [spins]` to estimate return-to-player
of the current weights / paytable / paylines configuration.
The GDScript implementation must stay in sync with the constants below.
"""
import random
import sys
from collections import defaultdict

ROWS, COLS = 3, 5

CHERRY, LEMON, ORANGE, PLUM, WATERMELON, STAR, HORSESHOE, MONEYBAG, \
    BELL, BAR1, BAR2, BAR3, SEVEN, WILD, BONUS = range(15)

NAMES = ["cherry", "lemon", "orange", "plum", "watermelon", "star",
         "horseshoe", "moneysack", "bell", "1bar", "2bar", "3bar",
         "777", "wild", "bonus"]

WEIGHTS = {
    CHERRY: 34, LEMON: 32, ORANGE: 30, PLUM: 26, WATERMELON: 24,
    STAR: 20, HORSESHOE: 17, MONEYBAG: 14, BELL: 12, BAR1: 10,
    BAR2: 8, BAR3: 6, SEVEN: 5, WILD: 11, BONUS: 6,
}

# pay per line, in LINE BET units, for 2 / 3 / 4 / 5 in a row from the left
# (2-of-a-kind pays only for the three cheapest fruits)
PAYTABLE = {
    SEVEN:      [0, 250, 1000, 5000],
    BAR3:       [0, 150, 600, 2500],
    BAR2:       [0, 100, 400, 1600],
    BAR1:       [0, 75, 300, 1200],
    BELL:       [0, 50, 200, 800],
    MONEYBAG:   [0, 40, 150, 600],
    HORSESHOE:  [0, 30, 100, 400],
    STAR:       [0, 25, 80, 300],
    WATERMELON: [0, 20, 60, 200],
    PLUM:       [0, 15, 40, 150],
    ORANGE:     [2, 12, 30, 120],
    LEMON:      [2, 10, 25, 100],
    CHERRY:     [2, 10, 25, 100],
    WILD:       [0, 500, 2000, 10000],
}

# scatter (BONUS chest): pays in TOTAL BET units + grants free spins
SCATTER_PAYS = {3: 2, 4: 10, 5: 50}
SCATTER_FREE_SPINS = {3: 10, 4: 15, 5: 20}

PAYLINES = [
    [1, 1, 1, 1, 1],
    [0, 0, 0, 0, 0],
    [2, 2, 2, 2, 2],
    [0, 1, 2, 1, 0],
    [2, 1, 0, 1, 2],
    [0, 0, 1, 2, 2],
    [2, 2, 1, 0, 0],
    [1, 0, 0, 1, 2],
    [1, 2, 2, 1, 0],
]
LINES = len(PAYLINES)


def rand_symbol(rng):
    total = sum(WEIGHTS.values())
    r = rng.randrange(total)
    acc = 0
    for sym, w in WEIGHTS.items():
        acc += w
        if r < acc:
            return sym
    return CHERRY


def spin_grid(rng):
    return [[rand_symbol(rng) for _ in range(ROWS)] for _ in range(COLS)]


def evaluate(grid, line_bet):
    """grid[col][row] -> dict with line wins, scatter pay and free spins."""
    total_bet = line_bet * LINES
    line_wins = []
    total = 0
    for li, line in enumerate(PAYLINES):
        cells = [grid[c][line[c]] for c in range(COLS)]
        base = WILD
        for sym in cells:
            if sym != WILD:
                base = sym
                break
        if base == BONUS:
            continue
        count = 0
        for sym in cells:
            if sym == base or sym == WILD:
                count += 1
            else:
                break
        if count >= 2 and PAYTABLE[base][count - 2] > 0:
            pay = PAYTABLE[base][count - 2] * line_bet
            total += pay
            line_wins.append((li, base, count, pay))
    scatters = sum(1 for c in range(COLS) for r in range(ROWS)
                   if grid[c][r] == BONUS)
    scatter_pay = 0
    free_spins = 0
    if scatters >= 3:
        scatter_pay = SCATTER_PAYS[min(scatters, 5)] * total_bet
        free_spins = SCATTER_FREE_SPINS[min(scatters, 5)]
        total += scatter_pay
    return {"total": total, "line_wins": line_wins,
            "scatters": scatters, "scatter_pay": scatter_pay,
            "free_spins": free_spins}


def simulate(spins, line_bet=1, seed=42):
    rng = random.Random(seed)
    wagered = 0
    returned = 0
    stats = defaultdict(int)
    hit_spins = 0
    fs_triggered = 0
    pending_fs = 0
    done = 0
    while done < spins or pending_fs > 0:
        if pending_fs == 0:
            wagered += line_bet * LINES
            done += 1
        else:
            pending_fs -= 1
        grid = spin_grid(rng)
        res = evaluate(grid, line_bet)
        returned += res["total"]
        if res["total"] > 0:
            hit_spins += 1
        if res["free_spins"]:
            pending_fs += res["free_spins"]
            fs_triggered += 1
        for _, base, count, pay in res["line_wins"]:
            stats[(base, count)] += 1
        if res["scatters"] >= 3:
            stats[("scatter", res["scatters"])] += 1
    rtp = returned / wagered * 100
    print(f"spins={done} (base={spins}) wagered={wagered} returned={returned}")
    print(f"RTP = {rtp:.2f}%   hit rate = {hit_spins / done * 100:.2f}%   "
          f"scatter triggers = {fs_triggered} ({fs_triggered / done * 100:.3f}%)")
    print("--- top events (count, avg pay in line bets) ---")
    for key, cnt in sorted(stats.items(), key=lambda kv: -kv[1])[:18]:
        print(f"   {str(key):24s} {cnt}")
    return rtp


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300000
    simulate(n)
