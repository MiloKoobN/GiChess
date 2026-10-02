# ♟️ GiChess — Next-Gen AI-Driven Chess Ecosystem

> **VERSION:** v0.1.3.0 Stable Alpha  
> **ENGINE:** Godot 4.x (GDScript)  
> **CORE ARCHITECTURE:** Asynchronous background multi-threading pipeline via `OS.execute_with_pipe`

**GiChess** is a high-performance, open-source chess application and analysis ecosystem built from the ground up using **Godot 4** and **GDScript**. 

Designed for both casual play and serious game review, it seamlessly connects to the world-class **Stockfish** engine via background multi-threading, delivering tournament-grade accuracy, smart time management, and instant tactical feedback in a premium light-minimalist interface.

---

## 🚀 Key Features (v0.1.3.0 Stable Update)

### 🔄 1. Advanced Multi-Premove Cascade & Ghost Vectors (Chess.com Style)
*   **`Sequential Queueing`** — Supports an infinite sequence of pre-planned moves (`premove_queue`) during the opponent's turn (e.g., `1. e2e4`, `2. g1f3`, `3. f1c4`).
*   **`Visual Ghosting Matrix`** — Setting a pre-move dampens the original piece to **30% opacity**, while generating a **75% transparent ghost clone** via native `TextureRect` nodes on the destination grid cell.
*   **`Continuous Dragging`** — True sequential dragging allows players to grab an active ghost figure directly from its visual mid-way point and drag it further across the board to extend the pre-move chain dynamically.
*   **`Smart Queue Flush`** — Clicking any empty cell or a double-click on the selected unit fires a clean `cancel_premove()` flush, instantly wiping all paths and resetting cell highlights.

### 🤖 2. Precision Stockfish Calibration & Centipawn Loss Analysis (Lichess Style)
*   **`Humanized Low-Tier AI`** — Engine configuration is decoupled from volatile ELO models. Levels 1 and 2 utilize native `Skill Level` (0-20) paired with strict depth limits (**depth 1** and **depth 2**), resulting in organic, human-like tactical blunders.
*   **`Strict Centipawn Loss Evaluation`** — Position metrics calculate raw **Centipawn Loss delta values**, eliminating false `!!` markers in standard opening lines and preventing unnecessary `?` tags during forced mate responses.
*   **`Interactive History Navigation`** — Click directly on any historical move inside the `RichTextLabel` log to instantly jump to that position, update engine arrows, and see real-time chess-standard annotations:
    *   🔴 **`??` Blunder** (`delta <= -2.0`) — Catastrophic drop in advantage.
    *   🟠 **`?` Mistake** (`delta <= -0.8`) — Serious tactical or positional oversight.
    *   🟡 **`?!` Inaccuracy** (`delta <= -0.35`) — Minor position slip.
    *   🟢 **`!` Best Move** (`delta >= 0.0`) — Optimal engine recommendation.

### 🎨 3. Premium Light-Minimalist UI Overhaul & Stability
*   **`6px Rounded Minimalist Design`** — Fully transitioned into a clean light theme (**Background `#eeeeee`**, **side panels `#ffffff`**, **text `#222222`**). UI buttons feature an interactive hover effect triggering a smooth blue (`#4b648a`) flash.
*   **`Mid-Air Drag Shielding`** — Injected `end_drag()` locks right before calling `show_game_over_screen()`, preventing the active piece from floating endlessly behind the cursor if a sudden checkmate occurs.

---

## 📊 Core Feature Matrix

| Module | Implementation Method | UI Node Type | Performance Impact |
| :--- | :--- | :--- | :--- |
| **Stockfish Pipeline** | Multi-threaded Background Worker | `Thread` / `OS Pipes` | **0% UI Freeze** / Asynchronous |
| **Premove Engine** | Array-based Queue Optimization | `TextureRect` (Opacity) | Ultra-lightweight memory profile |
| **Move Notation Log** | Centipawn Loss Delta Matcher | `RichTextLabel` (BBCode) | Buffered thread-safe rendering |
| **App Asset Render** | Programmatic Lanczos Interpolation | `Image` / `DisplayServer` | Runs once upon startup |

---

## 📈 Roadmap & What's Next (The Dawn of GiChess v0.2.0.0!)
The `0.1.x` alpha branch is officially frozen and stabilized. We are shifting gears to construct the foundational pillars of the next major architectural leap.

```diff
+ [UPCOMING v0.2.0.0] Tactics Puzzles Module: Parsing official FEN databases from local JSON files.
+ [UPCOMING v0.2.0.0] External PGN Importing: Paste raw text notations straight into the analysis suite.
```

---

## 🛠️ Installation & Launch Guide

1. Go to the **Releases** section on the right side of this GitHub page and download the latest archived build (e.g., `GiChess-v0.1.3.0.zip`).
2. Extract the downloaded ZIP archive into any folder on your computer.
3. Ensure that the `bin/` directory containing the Stockfish engine is kept in the same folder as the main executable.
4. Launch the game by double-clicking **`GiChess.exe`** (or the respective binary on macOS/Linux).

***
GiChess is actively developed and open for contributions. Fire it up, analyze your grandmaster lines, and dominate the board! 🏆🔥
