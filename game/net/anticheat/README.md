# Anti-cheat

Server-side only. Nothing here is sent to or read from the client beyond
what the protocol already carries. One `AntiCheat` per `GameInstance`.

## Hooks

Where the game calls in, and what it does with the answer:

| Game code | Hook | Effect |
| --- | --- | --- |
| `GameInstance.update_state` | `check_state` | A report the body could not have made is dropped; the pawn keeps its last accepted position. |
| `GameInstance.handle_shot` | `check_shot` | The shot is dropped, or runs with the origin and rewind the server allows. |
| `GameInstance.build_snap` | `sees` | An enemy the receiver's body cannot see is carried at `HIDDEN_Y` with no yaw or pitch. |
| `GameInstance._spawn_pawn` / `remove` | `on_spawn` / `on_leave` | Per-body state starts fresh on each life and is dropped on leave. |
| `GameInstance.handle_set_cheats` | `enforce_movement` | Movement checks pause while server cheats are on. |
| `GameServer._broadcast_snaps` | one `build_snap(pid)` per receiver | Each client gets its own snapshot. |
| `GameServer._on_instance_kick` | `peer_kicked` | The peer is told why and disconnected. |

`"anticheat": false` in the lobby config turns everything off; the checks
in `tools/anticheat_check.gd` use it to prove the hooks are the only path.

## Checks

| File | Catches | Decision |
| --- | --- | --- |
| `ac_movement.gd` | Instant long teleports | Drop, resync after 2 s as one `teleport` strike. Speed itself is not judged: air strafing has no ceiling in this movement model. |
| `ac_flight.gd` | Hovering, standing inside walls | Drop, `flight` or `noclip` strike. |
| `ac_shots.gd` | Fire-rate hacks, shots from elsewhere, rewind abuse, aim far off the reported view | Drop or correct, `fire_rate` / `shot_origin` / `aim_view` strikes. |
| `ac_culling.gd` | Wallhacks and aimbots that read the snapshot | Enemy left out of the snapshot until in line of sight. |
| `ac_violations.gd` | Repeat offenders | Kick thresholds per strike kind inside a 60 s window. |

## What it does not do

- Judge aim on a visible target. A perfect flick at someone in view is
  indistinguishable from a good player on a single shot; only statistics
  over many shots could say more, and that is not built.
- Hide hit and tracer events. Those go to everyone as before, so a shot's
  origin still reveals a shooter through a wall.
- Rewrite what a client renders. A kick shows as a disconnect.

Corner culling runs in GDScript today; see `tools/anticheat_check.gd` for
the per-ray cost. It is the first candidate for the C++ move.
