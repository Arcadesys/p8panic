Pyramid panic is a game played by 3-4 players that focuses on redirecting attacks

All players have cursors with the following three modes

attacker- points a pyramid that is 8px high toward a defender. an attacker may only be places when successfully pointed at a defender. the player may choose to point an attacker at their own defender, in which case that attack scores no points. (It does, however, count for purposes of calculating overcharge, below)

defender - places a defender. A player must _always_ have a live defender in play; if they fail to place a defender within 10 seconds of losing their last defender, they are out of the game.

- capture - allows for the capture and re-placement of enemy pieces attacking your defender.

after every piece placement, recalculate the score of the game.


# Scoring

Every piece placed either scores 1 point or 0 points.

- attackers succeed if there are 2+ attackers pointed toward the same defender. if that attacker is pointed at a defender of its own color, it scores no points.
- Defenders succeed if there are 0-1 attackers pointed at the same defender.


Every player has six pieces to place, totalling 36 for a game with max players.

# Overcharge (capture)
if a defender has 3+ pieces pointed at it, that defender is considered _overcharged_ and entitles its owner to perform a capture action. from the capture cursor, the defender player may pick up any attacker attacking that defender. they may then place that piece, maintaining its color, anywhere on the playfield.

The game continues for 3 minutes or until player 1 ends the game early by holding both buttons down for five seconds. Highest score wins.
# Pyramid Panic

_Beta Rules – last updated 2025‑05‑28_

Pyramid Panic is a **real‑time tactical geometry brawl** for **3–4 players**. Armed with razor‑sharp pyramids and plucky Defenders, you’ll redirect attacks, overload opponents, and steal their firepower—all in a frantic three‑minute skirmish. Easy to learn, wicked to master.

---

## Components

| Piece | Per Player | Purpose |
|-------|------------|---------|
| **Pyramids** | 6 | Deployed as **Attackers** OR **Defenders**. 
Each is an 8 px‑tall triangle that must point at a Defender. |
| **Defender** |  (must always be on the field) | Soaks up attacks and unlocks **Capture** moves when overloaded. |

*(The current build is digital—no physical bits required. Grab the PICO‑8 cart and dive in.)*

---

## Objective

Rack up the most points before the match timer hits **3 minutes** – or before Player 1 triggers **Sudden Death** with a five‑second double‑button press.

---

## The Three Cursor Modes

1. **Attack (red)** – Plant a pyramid that immediately points at any Defender (yes, even your own).
2. **Defend (blue)** – Drop or relocate your lone Defender. Lose your last Defender and you have **10 seconds** to place a new one or you’re out.
3. **Capture (gold)** – Unlocked automatically when your Defender is **overcharged** (3+ pyramids aimed at it). Snatch one attacking pyramid and redeploy it anywhere, keeping its color.

---

## How a Turn Works

Play is simultaneous and lightning‑fast:

1. **Select** a cursor mode (Attack, Defend, or Capture).  
2. **Place** your piece on the arena grid.  
   - Attacks & Captures must point at a Defender.  
   - You can never exceed six pyramids in play; you will need to **capture** other pyramids to continue influencing the game!  
3. **Re‑score** every Defender immediately.  
4. **Pass** to the next player (< 2 seconds).

---

## Scoring

| Situation | Points Awarded |
|-----------|---------------|
| Defender has **0–1** pyramids aimed at it | +1 to that Defender’s owner |
| Defender has **2+** pyramids aimed at it | +1 to *each* attacking pyramid’s owner (except friendly‑fire) |
| Pyramid aimed at its own Defender | 0 points (still counts toward overcharge) |

### Overcharge Bonus  
When a Defender absorbs **3+** incoming pyramids, its owner gains an immediate **Capture** move.

Keep a running tally on‑screen. Highest score at the buzzer wins.

---

## Sudden Death (Optional)

Player 1 can end the match at any time by pausing the game and selecting "finish game." that will instantly tally the scores.
---

## Designer Notes

These rules are still in flux—tell us what breaks, what sings, and what devilish pyramid tech you invent. Ping **@HouseArcade** on Bluesky or hop into the Discord to join the playtest squad!

---

### TL;DR

**Attack to score. Defend to survive. Capture when overloaded. Three minutes. Mayhem. Go!**