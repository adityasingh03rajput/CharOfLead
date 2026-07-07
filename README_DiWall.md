# Di-Wall

A dual-dimension local PvP prototype built in Godot 4.x. The world alternates
every **15–45 seconds** between two States that share one `Main.tscn`:

- **State A — 3D Ground-Walk maze.** Player 1 (Red Soldier) is powerful & armed;
  Player 2 (Blue Assassin) is unarmed and evades. Normal gravity.
- **State B — 2D Wall-Walk cross-section.** Player 2 (Blue Assassin) is powerful:
  walks on floors/walls/ceilings and fires a stealth dart. Player 1 is unarmed.

No scene changes on swap — the inactive environment is hidden and set to
`PROCESS_MODE_DISABLED`.

## Controls

| Action | Player 1 (Red Soldier) | Player 2 (Blue Assassin) |
|---|---|---|
| Move | `W` `A` `S` `D` | Arrow keys |
| Jump | `Space` | `/` (slash) |
| Fire (only when armed) | `F` | `.` (period) |
| Cycle 3D camera | `C` | — |
| Force dimension swap (debug) | `P` | — |

Fire only works for the dominant player in the current State (enforced by
`GameManager.is_armed()`), so the "unarmed" role can't shoot.

## Architecture

| File | Role |
|---|---|
| `Scripts/GameManager.gd` (Autoload) | Random swap timer, `mode_changed`/`swap_incoming` signals, **shared cross-dimension health**, combat routing (`apply_damage`, `is_armed`), win/lose. |
| `Scripts/Main.gd` | Shows the active environment, disables the inactive one. |
| `Scripts/Player3D.gd` | 3D fighter: camera-relative movement, jump, Red's hitscan. |
| `Scripts/WallWalkingPlayer2D.gd` | 2D fighter: surface-normal wall-walk, jump, Blue's line-of-sight stealth dart. |
| `Scripts/CameraController3D.gd` | Bird's-Eye → Isometric → Third-Person on `toggle_camera`. |
| `Scripts/HUD.gd` | Health bars, mode banner, red/blue swap flash, win banner. |

Health is owned by `GameManager` (not the bodies), so damage persists across
swaps — hitting P2 in 3D still counts when P2 becomes the 2D assassin.

Bodies register in dimension-namespaced groups (`p1_body_3d`, `p2_body_2d`, …)
so a weapon's raycast can only ever match a body in its own dimension.

## Test checklist (run `Main.tscn`)

1. **Boot** — starts in State A (3D). Output shows `GameManager: Next swap in ...`.
   HUD shows two full health bars + "STATE A - 3D".
2. **Camera** — press `C`: view cycles top-down → 45° iso → over-the-shoulder.
3. **3D combat** — as Red (WASD), aim at Blue and press `F`; Blue's health bar drops.
   Blue pressing `F` does nothing (unarmed in 3D).
4. **Swap** — press `P` (or wait). Screen flashes, State B (2D) appears; ~3s before
   an automatic swap you'll see a warning flash + `SWAP INCOMING`.
5. **Wall-walk** — as Blue (arrows) walk into the left/right wall and up onto the
   ceiling; the body rotates to align to each surface. `/` jumps off the surface.
6. **2D combat** — as Blue press `.`; if Red is in line of sight (no wall between),
   Red's health drops. Walls block the dart.
7. **Win** — drain a player's health to 0: timer stops and "PLAYER N WINS!" shows.

## Known limitations / next polish

- **Shared keyboard:** true local 2-player; both schemes are on one keyboard.
- **2D wall-walk corners:** `_detect_surface()` casts a single downward ray. Inner/
  outer maze corners would benefit from additional front/back probes.
- **Placeholder art:** capsules (3D) and colored rects (2D). The `*.zip` asset packs
  (mocap, pixel-art warrior) in the project root are not yet wired in.
- **No respawn/round system:** first KO ends the match.
- I authored this by code review; it has **not** been run in the Godot editor here.
  Work through the checklist above and paste any errors from the Output/Debugger
  panel and I'll fix them.
