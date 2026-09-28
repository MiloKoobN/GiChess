# ♟️ GiChess — Next-Gen AI-Driven Chess Ecosystem

GiChess is a high-performance, open-source chess application and analysis ecosystem built from the ground up using **Godot 4** and **GDScript**. 

Designed for both casual play and serious game review, it seamlessly connects to the world-class **Stockfish engine** via background multi-threading, delivering tournament-grade accuracy, smart time management, and instant tactical feedback.

---

## 🚀 Key Features (v0.1.2.0 Alpha)

* **🤖 Asynchronous Stockfish Integration:** Full UCI-compliant communication with the Stockfish engine running on a dedicated background thread, preventing UI freezes during high-depth calculations.
* **🕒 Fischer Time Increment Controls:** Supports FIDE-compliant time formats (including **5+5, 10+10, 30+30, 10+15**) with a multi-level nested `MenuButton` interface that smoothly flies out to the right [1.1.2', 1.1.9', 1.3.7].
* **🔬 Premium Interactive Log:** Click directly on any historical move (e.g., `Nf3`) to instantly jump to that position, update engine arrows, and see real-time evaluations. Features an elegant **Green hover effect** on a dark background (`#333333`).
* **⚙️ Advanced Engine Time Management:** Fixed critical Move 6 over-calculation bugs. Stockfish now intelligently scales its thinking speed based on its remaining clock (`clamp(400ms to 4000ms)`), eliminating accidental time losses.
* **🔄 Flawless Board & Notation Flipping:** FIDE-compliant grid inversion for both local matches and analysis. Coordinates, ranks (`1-8`), files (`a-h`), and engine arrows dynamically reverse instantly with zero visual overlap.
* **📊 Contrast Shield Evaluation Bar:** The dynamic thermometer widget (`eval_bar`) features a symmetric **2-pixel dark graphite border** on both sides, ensuring it never blends into the light panel background.

---

## 📈 Roadmap & What's Next (The Grand Finale of 0.1.x)

This is the **final patch of the 0.1.x alpha branch**. We are officially freezing this stage to prepare for the massive transition to **GiChess v0.2.0.0**!

- [ ] 🎨 **Visual Refinements:** Fresh aesthetic UI updates, theme polishing, and subtle board design upgrades.
- [ ] 🐛 **Micro-Bug Hunting:** A thorough sweep to squash remaining edge-case bugs, improve multi-threading engine safety, and ensure total layout stability.

---

## 🛠️ Requirements & Installation

1. Clone or download this repository.
2. Open the project using **Godot 4.x**.
3. Place your preferred Stockfish binary into the `res://bin/` directory and ensure the path points to `stockfish.exe` (or `stockfish` on macOS/Linux).
4. Run the project directly from the Godot Editor or export it as an executable.

*GiChess is actively developed and open for contributions. Fire it up, analyze your grandmaster lines, and dominate the board!* 🌟
