# ♟️ GiChess — Next-Gen AI-Driven Chess Ecosystem

GiChess is a high-performance, open-source chess application and analysis ecosystem built from the ground up using **Godot 4** and **GDScript**. 

Designed for both casual play and serious game review, it seamlessly connects to the world-class **Stockfish engine** via background multi-threading, delivering tournament-grade accuracy and instant tactical feedback.

---

## 🚀 Key Features

* **🤖 Asynchronous Stockfish Integration:** Full UCI-compliant communication with the Stockfish engine running on a dedicated background thread, preventing UI freezes during high-depth calculations.
* **🔬 Advanced Analysis Room:** Dynamic evaluation tracking with real-time tactical markers (Blunders `??`, Mistakes `?`, Inaccuracies `?!`, Brilliant moves `!!`) [Lichess]. 
* **🔄 Flawless Board Flipping:** FIDE-compliant grid inversion for both local matches and analysis. Coordinates, ranks (`1-8`), files (`a-h`), and engine arrows dynamically reverse instantly based on your perspective [Lichess].
* **🎨 Side Selection & Color Picker:** Play as White, Black, or choose Random. The game automatically handles turn execution, board flipping, and immediate AI responses.
* **⚙️ Tournament Logic:** Fully integrated rules including 3-fold repetition check, 50-move rule, insufficient material draw detection, and en passant captures.

---

## 📈 Current Project State: **v0.1.1.0 Alpha**

The core gameplay loop and the Analysis module are **officially stable**! You can now play full matches, reverse perspectives, and review your chess games with static debut caching (`Advantage: +0.3` and automatic `e2-e4` guidance on Move 0) without any game-breaking crashes [Lichess].

---

## 🗺️ Roadmap (What's Coming in v0.1.2.0)

- [ ] 🕒 **Fischer Time Increment:** Custom settings to add extra seconds to the clock after every legal move to prevent time-scrambles.
- [ ] 📊 **Polished Evaluation Bar:** Smooth real-time tweening and enhanced visual layout for the vertical thermometer widget.
- [ ] 💎 **Performance Optimization:** Edge-case bug hunting, multi-threading optimizations, and code refactoring for flawless stability.

---

## 🛠️ Requirements & Installation

1. Clone or download this repository.
2. Open the project using **Godot 4.x**.
3. Place your preferred Stockfish binary into the `res://bin/` directory and ensure the path points to `stockfish.exe` (or `stockfish` on macOS/Linux).
4. Run the project directly from the Godot Editor or export it as an executable.

*GiChess is actively developed and open for contributions. Fire it up, analyze your grandmaster lines, and dominate the board!* 🌟
