# Ion Strikers - Architecture Plan and Agent Handoff

Repository: `ion-strikers-game`

## Execution Gate: Only Three Phases Are Authorized

This document is the architectural direction for the Ion Strikers rebuild. **Do not implement the game yet.**

The agent must complete only the following three phases, in order, and then stop for review. Do not initialize the new Godot project, write production Go/C++ code, migrate assets, install project dependencies, or begin the implementation roadmap until explicitly instructed after Phase 3.

### Phase 1 - Read and Understand This Plan

This document should live in:

```text
plan/
```

Read the entire architecture plan before making any technical proposal. Treat the architecture decisions and priorities below as project constraints unless the Phase 3 proposal identifies a concrete technical conflict that should be raised for approval.

In particular, understand the intended foundations before reviewing the old implementation:

- Godot + C++ game client.
- Go Game API.
- One unified Godot/C++ Game Server implementation.
- Managed mode: one Game Server process can host multiple isolated `GameInstance`s, initially capped at 20 concurrent lobbies.
- Dedicated mode: the same Game Server binary runs one preloaded lobby with GameInstance capacity `1/1`.
- Classic and Deathmatch are the initial modes.
- Create Game / Join Game is the initial multiplayer UX; competitive matchmaking comes later.
- QUIC is the realtime transport, using DATAGRAM and reliable streams according to semantics.
- Strong state ownership and deterministic cleanup are higher priority than premature optimization.
- Delayed, asynchronous, non-atomic lobby persistence should exist as a foundation for future recovery, but V1 must **not** implement automatic host takeover, failover, migration, leases, or reassignment.
- Arcade responsiveness is a core requirement.
- Existing models, rigs, animations, HUD, menus, and successful presentation work should be preserved/migrated wherever practical instead of being needlessly redesigned.

Do not produce implementation code during this phase.

### Phase 2 - Read the Existing PlayCanvas Implementation

The current implementation will be available under:

```text
previous-impl/
```

Read the existing source code and assets carefully before proposing the rebuild. The purpose is **not** to copy its architecture into Godot. The purpose is to understand what Ion Strikers already is, what works, what content exists, and what behavior the rebuild must preserve.

Inspect the implementation broadly enough to understand at least:

- Player models and model formats.
- Skeletons, rigs, animation clips, animation names, and how animations are selected/blended today.
- Weapon models, laser effects, hit effects, death effects, sounds, and other presentation assets.
- Existing maps, spawn layouts, arena structure, collision assumptions, and map-specific gameplay behavior.
- Movement behavior: acceleration, speed, strafing, jumping, air behavior, friction/deceleration, camera behavior, and anything that contributes to the arcade feel.
- Weapon behavior: firing cadence, hitscan/projectile behavior, cooldowns, damage, feedback, hit confirmation, death, and respawn behavior.
- Classic rules and Deathmatch rules as they exist today.
- Current lobby/game lifecycle and where state currently leaks between games.
- Current networking/state synchronization behavior, only as a behavioral reference; do not preserve a poor networking architecture simply because it exists.
- Current HUD in detail.
- Main menus, Create Game UI, Join Game/server browser UI, in-game menus, settings, scoreboards, overlays, crosshair, health/ammo/score presentation, death/results UI, and transitions.
- Fonts, icons, textures, colors, layout, spacing, animations, and other UI assets used by the HUD/menus.
- Existing project asset formats and which can migrate directly to Godot versus which need conversion.
- Input bindings and interaction behavior.
- Any gameplay constants/tuning values worth preserving initially.
- Any useful content pipeline conventions.

### Preserve the HUD and Menus

We **like the current HUD and menus and want to keep them**.

Do not approach the Godot rewrite as a visual redesign. The default assumption should be to reproduce/migrate the existing HUD, menus, game presentation, and established visual identity as faithfully as practical while reimplementing them cleanly using Godot UI patterns.

If an element must change because PlayCanvas-specific technology does not map directly to Godot, preserve the user experience and appearance first and document the required implementation difference.

Likewise, reuse existing compatible models and animations. Do not replace working art merely because the engine changed.

### Preserve Feel, Not Architectural Mistakes

The existing implementation is the reference for:

- gameplay identity,
- feel,
- visual presentation,
- assets,
- maps,
- rules,
- HUD,
- menus,
- animations,
- tuning worth preserving.

It is **not** the architectural template for the new codebase.

Specifically, do not reproduce state leakage, global mutable state, tightly coupled client/server concerns, or other structural problems merely because they exist under `previous-impl/`.

During Phase 2, do not start implementing the replacement.

### Phase 3 - Propose the Implementation Plan in Markdown

After Phase 1 and Phase 2 are complete, create a proposed implementation plan under:

```text
implementation-plan/
```

Use Markdown. A sensible default filename is:

```text
implementation-plan/IMPLEMENTATION_PLAN.md
```

The proposal must be based on **both** this architecture document and what was actually discovered in `previous-impl/`.

The implementation plan should include, at minimum:

1. A concise summary of the existing implementation as understood from `previous-impl/`.
2. An asset inventory and migration strategy for models, rigs, animations, maps, textures, materials, audio, effects, HUD assets, and menu assets.
3. A specific plan for preserving the existing HUD and menu UX in Godot.
4. A description of the existing gameplay feel and the concrete tuning/behavior that should be preserved initially.
5. Any state-leakage or lifecycle problems discovered in the old implementation and how the new ownership model prevents them.
6. The exact proposed repository tree.
7. The exact Godot project structure and current official bootstrap method after verifying the current stable Godot and compatible `godot-cpp` versions.
8. C++ library/module boundaries and where pure/shared game logic should live.
9. Go Game API package/module boundaries.
10. Unified Game Server structure, including managed `0..20` lobby capacity and dedicated preloaded `1/1` mode using the same binary.
11. `GameServer -> GameRegistry -> GameInstance -> Match -> Round` ownership/lifetime design, adjusted as needed for Classic versus Deathmatch.
12. Game/lobby creation and join flows.
13. QUIC library recommendation with current-platform/build/licensing justification.
14. QUIC DATAGRAM versus reliable-stream message design and proposed stream topology.
15. Versioned network protocol and serialization recommendation.
16. Simulation tick, input submission, snapshot, interpolation, prediction, and reconciliation approach appropriate for a fast arcade FPS.
17. Delayed/non-atomic lobby persistence design, including a versioned logical snapshot schema and asynchronous persistence boundary.
18. Explicit confirmation that automatic recovery onto another managed host is **not** being implemented yet.
19. Observability, state dumps, structured logging, metrics, and debugging strategy.
20. Unit, lifecycle, cross-lobby isolation, network, integration, persistence, and soak-testing strategy.
21. CI/build/version-pinning strategy.
22. Security boundaries.
23. Risks, open questions, and decisions that require approval.
24. A detailed future implementation sequence with acceptance criteria for each milestone.

For important choices, explain:

- what is recommended,
- why it is recommended,
- what alternatives were considered,
- why those alternatives were rejected or deferred.

Do not invent details about the old implementation. Cite file paths/classes/assets from `previous-impl/` inside the proposal whenever they materially justify a migration or architecture decision.

## Stop Condition

After writing the Phase 3 Markdown implementation plan, **STOP**.

Do not proceed to repository bootstrap or implementation.
Do not create the Godot project.
Do not write production C++ or Go.
Do not begin asset conversion.
Do not implement networking.
Do not implement the Game API or Game Server.

Wait for the next instruction, which will define the next authorized phases.

---

# Architecture Plan

The remainder of this document is the architecture plan to be read during Phase 1.

**ION STRIKERS**

**Godot Multiplayer Architecture & Implementation Plan**

A clean rebuild plan for a fast, arcade-style laser FPS using Godot/C++, a Go control plane, authoritative QUIC networking, explicit state ownership, and a unified managed/dedicated game-server model.

| **PLAN ONLY** | **GODOT + C++** | **GO API** | **QUIC** |
|---------------|-----------------|------------|----------|

**Status** Architecture approval document. No repository or implementation should be created from this document until the plan is reviewed.

**Repository** ion-strikers-game

**Initial modes** Classic and Deathmatch

**Primary design priorities** State ownership -> debuggability -> server authority -> network correctness -> maintainability -> performance

# 1. Executive Summary

Ion Strikers is being rebuilt from the existing PlayCanvas version into a Godot-based multiplayer FPS while preserving its fast arcade character. The architecture intentionally separates the public control plane from realtime simulation and uses one reusable Game Server implementation for both managed hosting and traditional dedicated hosting.

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Core topology</p>
<p>Game clients use the Go Game API for discovery, creation and join authorization. Realtime gameplay then connects directly to the Godot/C++ Game Server over QUIC. The Game API is not in the realtime packet path.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>CLIENT<br />
|\<br />
| \ HTTPS / HTTP/3 - discovery, create, join<br />
| --> GAME API (Go)<br />
| |<br />
| | internal control / registration<br />
| v<br />
+==== QUIC ====> GAME SERVER (Godot + C++)<br />
|<br />
+-- GameInstance A<br />
+-- GameInstance B<br />
+-- ...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

The first official managed deployment is intentionally small: one Game API and one Game Server process with configurable capacity for up to 20 simultaneous GameInstances. A traditional dedicated server uses the exact same Game Server binary but starts with one preloaded lobby and a GameInstance capacity of 1/1.

The design explicitly rejects a second dedicated-server codebase, peer-to-peer authority, listen-server authority, a competitive matchmaking system in V1, and global mutable gameplay state.

# 2. Product and Engineering Goals

| **Goal**                   | **Implication**                                                                                                                                 |
|----------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------|
| Fast arcade FPS feel       | Immediate mouse/camera response, aggressive movement tuning, local prediction, minimal downtime, no realism systems unless gameplay needs them. |
| Classic + Deathmatch first | Create Game and Join Game are the initial UX. Competitive queues, MMR, party lobbies and ranked systems are future work.                        |
| Clean state boundaries     | Every lobby/game owns its mutable state. Match and round state are scoped and destroyable. No cross-game leakage.                               |
| Authoritative servers      | Clients submit input/intent. The Game Server owns health, hits, scores, spawn validity, match state and rules.                                  |
| Easy to debug              | Structured logs, IDs, state transitions, state dumps, metrics and lifecycle tests are architectural requirements.                               |
| Reuse existing content     | Migrate compatible models, rigs and animations instead of recreating assets unnecessarily.                                                      |
| Simple V1 operations       | One Game API + one Game Server. Horizontal scheduling and game migration are deliberately deferred.                                             |

# 3. System Boundaries

## 3.1 Game Client - Godot + C++

> • Owns presentation, input collection, camera, audio, effects, animation, client prediction and interpolation.
>
> • Uses current Godot scene/node/resource patterns, with C++ through GDExtension for core systems.
>
> • Does not decide authoritative damage, kills, score, spawn legality or match outcome.

## 3.2 Game API - Go

> • Single public control-plane entry for Create Game, Join Game, game discovery and server metadata.
>
> • Coordinates with Game Servers through an internal management interface.
>
> • May issue short-lived join credentials and enforce build/protocol compatibility.
>
> • Does not proxy realtime gameplay traffic.

## 3.3 Game Server - Godot + C++

> • Authoritative realtime simulation and game rules.
>
> • Hosts multiple isolated GameInstances when configured for managed hosting.
>
> • Hosts one preloaded GameInstance when configured as a traditional dedicated server.
>
> • Exposes health/readiness/capacity and a private management surface to the Game API.

# 4. One Game Server, Two Hosting Policies

Managed and dedicated hosting are not separate products. They are policies around the same GameServer, GameRegistry and GameInstance implementation.

| **Aspect**              | **Managed hosting**           | **Dedicated hosting**                    |
|-------------------------|-------------------------------|------------------------------------------|
| Binary                  | Ion Strikers Game Server      | Same binary                              |
| Lobby creation          | Dynamic through Game API      | Preloaded at process startup             |
| GameInstance capacity   | Initially 0..20               | Exactly 1..1                             |
| Lobby lifetime          | Created/destroyed dynamically | Usually survives across many matches     |
| Discovery               | Registered with Game API      | Optionally registered with same Game API |
| Gameplay implementation | Identical                     | Identical                                |
| QUIC protocol           | Identical                     | Identical                                |

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Important meaning of 1/1</p>
<p>A dedicated server configured as 1/1 has one hosted lobby, not one player. That lobby can still allow 8, 12, 16 or another configured number of players.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 4.1 Initial managed deployment

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>1 Game API<br />
1 Game Server<br />
GameInstance capacity: 0 / 20 ... 20 / 20<br />
Modes: Classic | Deathmatch</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

No distributed scheduler is needed in V1. The Game API can be configured with exactly one managed Game Server. The Game Server reports its capacity and rejects creation when full.

## 4.2 Future scaling boundary

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>+--> Game Server A<br />
|<br />
Game API --------+--> Game Server B<br />
|<br />
+--> Game Server C</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Future scheduling becomes a Game API control-plane concern. Gameplay code underneath GameInstance does not need to know whether another Game Server exists.

# 5. State Ownership and Lifecycle

The rebuild must make state leakage structurally difficult. Mutable state belongs to the narrowest meaningful lifetime and is destroyed with that lifetime.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Process<br />
+-- GameServer<br />
+-- process-scoped services<br />
+-- QUIC transport<br />
+-- GameRegistry<br />
+-- GameInstance A<br />
| +-- players<br />
| +-- match<br />
| +-- round (Classic when applicable)<br />
| +-- entities<br />
| +-- timers<br />
| +-- replication<br />
| +-- mode state<br />
+-- GameInstance B</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Lifetime**         | **Owns**                                                           | **Must not own**                                      |
|----------------------|--------------------------------------------------------------------|-------------------------------------------------------|
| Process / GameServer | Config, logging, metrics, server identity, transport, registry     | Current score, current round, lobby players           |
| GameInstance         | Lobby metadata, connected players, mode, map context, active match | Other lobbies state                                   |
| Match                | Match score, limits, match-specific entities/timers                | Previous match state                                  |
| Round                | Round-only spawn/death/round score/timers                          | State needed across rounds unless explicitly promoted |
| Entity / Player      | Entity-local authoritative data                                    | Global game state                                     |

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Rule</p>
<p>Avoid mutable gameplay state in Godot Autoloads/singletons. Long-lived process services may exist globally, but lobby/match/round state must be explicitly reachable through its ownership tree.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 6. Explicit State Machines

## 6.1 Game Server lifecycle

| Starting -> Initializing -> Ready -> Draining -> ShuttingDown |
|-------------------------------------------------------------------|

## 6.2 Game/lobby lifecycle

| Creating -> WaitingForPlayers -> Active -> Ending -> Destroying -> Destroyed |
|-----------------------------------------------------------------------------------|

## 6.3 Match and round lifecycle

Deathmatch does not need to be forced into a round abstraction. A Deathmatch GameInstance can run a continuous match with join-in-progress, respawns and score/time limits. Classic may own a round state machine underneath the match.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Classic match<br />
MatchStarting -> RoundStarting -> RoundLive -> RoundEnding<br />
^ |<br />
+---------------- next round ----------+<br />
-> MatchEnding -> Results</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Every transition should log previous state, next state, reason, game_id, match_id, optional round_id, and simulation tick. Invalid transitions should fail visibly rather than silently mutating booleans.

# 7. Delayed Lobby State Persistence

The Game Server should periodically persist recovery-oriented lobby state, but persistence is explicitly not atomic with realtime simulation and must not become part of the authoritative per-tick hot path.

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>V1 persistence contract</p>
<p>Persist lobby state late / periodically. A persisted snapshot may trail live gameplay. The system accepts that the last few seconds or the latest transition may be missing after a crash. Do not block or stall the simulation to make every state transition durable.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 7.1 What should be persisted

| **Persist**                                                      | **Reason**                                                  |
|------------------------------------------------------------------|-------------------------------------------------------------|
| Game/lobby ID and schema version                                 | Recovery identity and compatibility                         |
| Mode and map configuration                                       | Recreate the intended lobby                                 |
| Server/lobby display metadata                                    | Restore discoverable state                                  |
| Configured player limits and rules                               | Rehydrate gameplay policy                                   |
| Current coarse lifecycle state                                   | Know whether the snapshot represented waiting/active/ending |
| Match identifiers and coarse score/state where useful            | Permit future best-effort recovery design                   |
| Player/session recovery metadata only if intentionally supported | Avoid blindly persisting volatile transport objects         |
| Snapshot sequence/version and timestamp                          | Detect staleness and order snapshots                        |

## 7.2 What should not be treated as durable truth

> • Per-frame transforms, render state, raw Godot Node references or pointers.
>
> • QUIC connection objects, stream handles or transient transport buffers.
>
> • Every simulation tick or every input packet.
>
> • An assumption that persistence is transactionally consistent with the exact live simulation instant.

## 7.3 Persistence mechanism requirements

> • Serialize a versioned logical LobbySnapshot / GameSnapshot, never arbitrary Godot scene objects.
>
> • Generate the snapshot from owned game state, then persist asynchronously or through a low-priority persistence path so disk/database latency cannot stall simulation.
>
> • Coalesce frequent changes and write after a configurable delay/interval plus selected coarse lifecycle events.
>
> • Expose last_persisted_at, last_persisted_version, persistence failures and queue/backlog metrics.
>
> • Persistence failure must be observable but should not crash an otherwise healthy active match unless a future policy explicitly requires it.

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Explicitly out of scope</p>
<p>Do not implement moving/recovering a lobby onto another managed Game Server in V1. Only design the persisted state format and boundaries so a future host could consume it. No failover coordinator, lease transfer, fencing protocol, automatic reassignment or live migration yet.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 8. QUIC Networking Model

QUIC should be used intentionally rather than as a single reliable TCP replacement. The Game Server exposes a realtime QUIC endpoint. The Game API can remain conventional HTTPS and may support HTTP/3 where useful.

| **Traffic**                      | **Preferred QUIC primitive**               | **Why**                                                                             |
|----------------------------------|--------------------------------------------|-------------------------------------------------------------------------------------|
| Movement/input samples           | DATAGRAM                                   | Newer input often supersedes stale input; loss should not block future input.       |
| Frequent world/player snapshots  | DATAGRAM                                   | A lost old snapshot should not hold a newer snapshot behind it.                     |
| Look/motion transient state      | DATAGRAM                                   | Latency matters more than perfect delivery.                                         |
| Handshake / protocol negotiation | Reliable stream                            | Must arrive and be interpreted correctly.                                           |
| Join authorization               | Reliable stream                            | Security and state transition must be reliable.                                     |
| Initial world state              | Reliable stream                            | Client needs a complete baseline before applying deltas.                            |
| Critical game events             | Reliable stream where semantics require it | Round/match transitions and authoritative control events cannot silently disappear. |

## 8.1 Protocol requirements

> • Explicit protocol and build versions.
>
> • Sequence numbers and simulation ticks for stale/reordered datagram rejection.
>
> • Stable game_id, player_id, entity_id and match/round identifiers.
>
> • Maximum message sizes, malformed packet handling and rate limits.
>
> • No direct serialization of Godot Nodes, Variants or scene-tree internals onto the wire.
>
> • Evaluate compact binary serialization deliberately; do not default to JSON for realtime state without justification.

## 8.2 Head-of-line blocking

Use separate reliable streams only where they represent meaningful independent traffic classes. Do not create one stream per tiny event, but avoid forcing unrelated reliable control traffic behind a single long transfer.

# 9. Arcade Feel and Responsiveness

Responsiveness is a core architecture requirement. Server authority must not make Ion Strikers feel network-bound.

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>input -> immediate local response -> local prediction<br />
-> send input to server -> authoritative simulation<br />
-> reconciliation when authoritative result returns</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

| **Area**       | **Requirement**                                                                                                  |
|----------------|------------------------------------------------------------------------------------------------------------------|
| Mouse / camera | Local, immediate, updated with rendering; never wait on network acknowledgement.                                 |
| Movement       | Fast acceleration, responsive strafing and direction changes, predictable jumping, tunable friction/air control. |
| Firing         | Immediate local laser/audio/animation feedback; server decides authoritative hit/damage/kill.                    |
| Remote players | Interpolated from server snapshots rather than direct transform snapping.                                        |
| Corrections    | Small prediction errors should be smoothed; invalid state is still corrected authoritatively.                    |
| Animation      | Presentation must follow gameplay quickly and must not introduce unnecessary animation locks.                    |

The plan should propose fixed simulation tick, input rate, snapshot rate and interpolation delay based on fast FPS requirements. These must be centralized configuration values, not magic constants scattered across systems.

# 10. Existing Models, Rigs and Animations

Existing PlayCanvas content should be treated as migratable production work, not disposable prototypes. The agent should inventory assets before rebuilding content.

| **Asset area**       | **Migration expectation**                                                                                           |
|----------------------|---------------------------------------------------------------------------------------------------------------------|
| Models               | Prefer direct Godot import or conversion to a Godot-friendly glTF/GLB pipeline where appropriate.                   |
| Skeletons / rigs     | Validate bone hierarchy, orientation, naming and scale before deciding retargeting is necessary.                    |
| Animations           | Preserve existing clips whenever compatible; do not hand-recreate working animation without a real incompatibility. |
| Materials / textures | Document differences in material/shader model and convert deliberately.                                             |
| Maps                 | Migrate geometry/content while adapting gameplay scene ownership to the new architecture.                           |
| Audio / effects      | Reuse compatible assets and keep presentation client-side where appropriate.                                        |

## 10.1 Godot animation architecture

> • Use current Godot AnimationPlayer / AnimationTree / state-machine or blend-space patterns as appropriate.
>
> • Keep authoritative gameplay state separate from visual animation state.
>
> • Derive remote animation from meaningful replicated gameplay state such as velocity, grounded state, firing and death events instead of replicating raw animation playback.
>
> • Do not let animation completion gate firing, turning or locomotion unless the gameplay rule intentionally requires it.

# 11. Game API Responsibilities

The Go API should remain small and boring. It is a public control plane and discovery layer, not a game simulation.

| **Initial responsibility** | **Notes**                                                                                 |
|----------------------------|-------------------------------------------------------------------------------------------|
| Create game                | Ask the configured managed Game Server to create a GameInstance if capacity is available. |
| List / discover games      | Expose joinable lobbies with mode, map, player counts, compatibility and useful metadata. |
| Join game                  | Validate game availability and return endpoint + short-lived join authorization.          |
| Game Server registration   | Track servers, capacity, health, build/protocol version and heartbeats.                   |
| TTL cleanup                | Remove stale server/lobby discovery entries when heartbeats stop.                         |
| Compatibility              | Reject incompatible clients/servers early.                                                |

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Not V1</p>
<p>No ranked matchmaking, MMR, party queues, competitive ready checks, tournaments, map pick/ban or multi-server scheduler.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 12. Player Flows

## 12.1 Create Game

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Client -> POST create request -> Game API<br />
Game API -> Game Server management API<br />
Game Server -> capacity check -> GameRegistry.create()<br />
Game API <- game metadata / join token<br />
Client ===== QUIC =====> Game Server -> correct GameInstance</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Create options should stay intentionally small for V1: Classic or Deathmatch, map, max players and optional display name/basic rule values.

## 12.2 Join Game

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Client -> GET games -> Game API -> joinable lobby list<br />
Client -> POST join game -> Game API<br />
Game API -> validates / coordinates slot<br />
Client <- endpoint + game_id + short-lived credential<br />
Client ===== QUIC =====> Game Server -> GameInstance</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

## 12.3 Dedicated server

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>Game Server starts<br />
-> loads dedicated configuration<br />
-> initializes QUIC<br />
-> creates configured GameInstance automatically<br />
-> capacity becomes 1/1<br />
-> optionally registers with Game API<br />
-> runs Match 1, clean teardown, Match 2, ...</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# 13. Repository and Godot Bootstrap Rules

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>Do not scaffold from model memory</p>
<p>Before implementation, verify the current stable Godot release, current godot-cpp compatibility and current official project/bootstrap guidance. Pin stable versions. Do not use beta/RC/dev/nightly builds and do not hand-invent an old project.godot/GDExtension layout.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Use GDExtension + godot-cpp as the default C++ integration unless research finds a strong reason to maintain a custom engine module/fork. Use the official Godot project manager/CLI/tooling wherever supported.

## 13.1 Proposed monorepo shape to validate during planning

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>ion-strikers-game/<br />
api/ # Go Game API<br />
game/ # Godot client project / presentation<br />
server/ # Godot headless Game Server entrypoint<br />
shared/<br />
game-core/ # pure/shared C++ gameplay primitives where practical<br />
protocol/ # versioned wire schemas + codecs<br />
networking/ # shared transport abstractions where appropriate<br />
assets/ # migrated source/content policy to be decided<br />
tests/<br />
tools/<br />
docs/<br />
adr/<br />
architecture/<br />
deploy/ # container/deployment assets later</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

This tree is a planning target, not a scaffold command. The agent should validate the exact Godot/GDExtension layout against current tooling before creating anything.

# 14. Observability and Debugging

Every important system should be inspectable without attaching a debugger and searching arbitrary globals.

| **Signal**        | **Minimum context**                                                                          |
|-------------------|----------------------------------------------------------------------------------------------|
| Structured logs   | server_id, game_id, match_id, optional round_id, player_id/connection_id when relevant, tick |
| State transitions | previous, next, reason, IDs, tick/time                                                       |
| Networking        | RTT, loss, bytes, datagram counts/drops, stream backpressure, disconnect reason              |
| Capacity          | max games, active games, available slots, total players                                      |
| Persistence       | last snapshot time/version, write latency, failures, queued/coalesced writes                 |
| Health/readiness  | process health, QUIC readiness, Game API management readiness, capacity                      |

Provide a developer-only logical state dump for GameServer/GameRegistry/GameInstance showing active games, players, entities, timers, match state, round state, replication state and current ticks. Protect or disable this in production-facing paths.

# 15. Security Boundaries

> • Never trust client position, health, damage, kills, score, weapon ownership or spawn validity.
>
> • Authenticate game joins and Game Server registration/control operations.
>
> • Validate message type, length, protocol version and state legality before applying network input.
>
> • Rate-limit abusive clients and ensure one malformed client cannot destabilize the entire multi-lobby process.
>
> • Keep internal Game Server management and debug surfaces out of the public player-facing path.
>
> • A connection/session must resolve to exactly one game_id; packets cannot mutate another GameInstance.

# 16. Testing Strategy

| **Test class**        | **Required behavior**                                                                                           |
|-----------------------|-----------------------------------------------------------------------------------------------------------------|
| C++ unit tests        | Game rules/state transitions independent of graphics where practical.                                           |
| Protocol tests        | Encode/decode, truncation, corruption, invalid type, oversize, stale sequence, incompatible version.            |
| Lifecycle tests       | Create/destroy matches and rounds repeatedly; verify owned state disappears.                                    |
| Cross-lobby isolation | Run multiple GameInstances concurrently and prove IDs/state cannot cross boundaries.                            |
| Managed capacity      | Create 20 games, reject the 21st, destroy randomly, immediately reuse freed slots.                              |
| Dedicated soak        | Run hundreds/thousands of matches inside the same preloaded 1/1 GameInstance without accumulating state.        |
| Integration           | API -> create -> discover -> join -> QUIC -> play -> end -> cleanup.                                     |
| Network conditions    | Latency, jitter, loss, reordering and duplication for datagram behavior and reconciliation.                     |
| Persistence           | Delayed snapshot writes, coalescing, stale snapshot versioning, persistence failures without simulation stalls. |

> **Important:** The roadmap below is retained as architectural background from the original plan. It is **not authorization to execute those phases**. The only authorized work right now is the three-phase review workflow at the top of this document. After reviewing `previous-impl/`, Phase 3 must produce a fresh implementation plan informed by the actual source tree, assets, HUD, menus, gameplay, and current behavior. Then stop.

# 17. Proposed Implementation Phases

| **Phase**                         | **Work**                                                                                                                                                 | **Acceptance**                                                                                                      |
|-----------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| 0 - Research and decisions        | Verify stable Godot, godot-cpp compatibility, official bootstrap path, C++ build/test stack, QUIC library, serialization, target platforms. Record ADRs. | No implementation; architecture choices are documented with rejected alternatives.                                  |
| 1 - Repository bootstrap          | Create monorepo using current official tooling and pinned versions. Establish formatting, basic CI and reproducible local setup.                         | Fresh clone can bootstrap/load projects using pinned stable tools.                                                  |
| 2 - Shared core and state model   | IDs, typed config, GameServer/GameRegistry/GameInstance ownership, lifecycle state machines, protocol foundations and structured logging.                | Lifecycle unit tests demonstrate explicit ownership and invalid transition detection.                               |
| 3 - Headless Game Server skeleton | Godot headless server startup, management API, QUIC listener shell, managed capacity and dedicated preloaded 1/1 policy.                                 | Managed 0..20 and dedicated 1/1 both run from the same binary.                                                      |
| 4 - Game API                      | Registration/heartbeat, create/list/join, compatibility and one configured managed Game Server.                                                          | Client/tool can create and discover a GameInstance through the API.                                                 |
| 5 - QUIC protocol                 | Handshake, authentication, reliable control streams, datagram input/snapshot lanes, connection-to-game routing and telemetry.                            | Two test clients connect to the correct GameInstance without cross-lobby leakage.                                   |
| 6 - Client skeleton               | Godot client states, Create/Join UI, server browser, connection/loading flow.                                                                            | Client can create or join and cleanly leave/rejoin another game.                                                    |
| 7 - First playable arena loop     | Spawn, movement, laser firing, authoritative hit/death, respawn, score, Classic/Deathmatch minimum rules.                                                | Two or more clients can complete a match with responsive controls and clean teardown.                               |
| 8 - Prediction and FPS quality    | Prediction, reconciliation, interpolation, snapshot tuning, later lag compensation where justified.                                                      | Normal latency does not make local movement/camera feel network-bound; remote motion is smooth.                     |
| 9 - Asset and animation migration | Inventory and migrate compatible player/weapon/map assets, rigs, animations, materials and effects.                                                      | Existing animations work through Godot presentation state without controlling authoritative outcomes.               |
| 10 - Delayed persistence          | Versioned lobby snapshots, delayed/coalesced writes, metrics and recovery-compatible schema.                                                             | Persistence trails live state by design, never stalls simulation, and can be read back in tests. No host migration. |
| 11 - Operational hardening        | Containers, health/readiness, soak tests, metrics, graceful draining/shutdown and deployment docs.                                                       | Server survives long-running multi-lobby and dedicated soak scenarios cleanly.                                      |

# 18. First Playable Milestone

> **1.** Start one Game API and one managed Game Server with capacity 20.
>
> **2.** Launch client and choose Create Game.
>
> **3.** Select Classic or Deathmatch and a map.
>
> **4.** Game API creates an isolated GameInstance on the Game Server.
>
> **5.** Creator connects directly to that GameInstance over QUIC.
>
> **6.** Second client opens Join Game, sees the lobby and joins.
>
> **7.** Existing player model/animation assets display correctly or have a documented conversion path.
>
> **8.** Players move with immediate, fast arcade response.
>
> **9.** Laser fire provides immediate local feedback while server validates hits.
>
> **10.** Server authoritatively resolves health, death, score and mode rules.
>
> **11.** Match ends and all match/round state is destroyed.
>
> **12.** Another match/game starts with no leaked players, entities, timers, replication state or scores.
>
> **13.** Delayed lobby persistence can snapshot recovery-oriented logical state without blocking the simulation.

# 19. Explicit Non-Goals for V1

| **Do not build yet**                           | **Reason**                                                |
|------------------------------------------------|-----------------------------------------------------------|
| Competitive matchmaking / MMR / ranked lobbies | Classic server-style Create/Join comes first.             |
| Automatic game migration or failover           | Persist state now; design takeover later.                 |
| Multi-Game-Server scheduler                    | One managed Game Server is enough for initial deployment. |
| Separate dedicated server implementation       | Same Game Server binary handles 1/1 dedicated policy.     |
| Peer-to-peer / listen-server authority         | Server remains authoritative.                             |
| Realtime gameplay through Game API             | Control plane stays out of data plane.                    |
| Global mutable gameplay managers               | Breaks state isolation and teardown guarantees.           |
| Engine fork without strong need                | Prefer standard stable Godot + GDExtension/godot-cpp.     |

# 20. Instruction to the Implementation Agent

<table>
<colgroup>
<col style="width: 1%" />
<col style="width: 98%" />
</colgroup>
<thead>
<tr class="header">
<th></th>
<th><p>First response is plan only</p>
<p>Before touching the repository, return a detailed implementation plan covering exact repository tree, current stable Godot/bootstrap method, C++/Go build boundaries, QUIC choice, protocol choice, state ownership, lifecycle, delayed persistence, testing, CI, security and phased acceptance criteria. Explain why each important choice was selected and what alternative was rejected.</p></th>
</tr>
</thead>
<tbody>
</tbody>
</table>

Do not create files, initialize the repository, install dependencies or implement code until that plan is reviewed and approved.

Optimize decisions in this order:

<table>
<colgroup>
<col style="width: 100%" />
</colgroup>
<thead>
<tr class="header">
<th>correct state ownership<br />
-> debuggability<br />
-> server authority<br />
-> network correctness<br />
-> maintainability<br />
-> performance</th>
</tr>
</thead>
<tbody>
</tbody>
</table>

# Appendix A. Architecture Decision Summary

| **Decision**          | **Chosen direction**                                                                       | **Rejected / deferred**                                                   |
|-----------------------|--------------------------------------------------------------------------------------------|---------------------------------------------------------------------------|
| Engine                | Current stable Godot, C++ via official GDExtension/godot-cpp unless research disproves fit | Unreleased Godot, model-memory scaffolding, custom engine fork by default |
| Control plane         | Go Game API                                                                                | Realtime gameplay proxying                                                |
| Realtime transport    | QUIC with DATAGRAM + multiple reliable streams where justified                             | Single reliable stream for everything                                     |
| Server implementation | One Godot/C++ Game Server binary                                                           | Separate managed and dedicated codebases                                  |
| Managed topology      | One server process, up to 20 isolated GameInstances initially                              | Process pool / distributed scheduler in V1                                |
| Dedicated topology    | Same binary, preloaded GameInstance, capacity 1/1                                          | Special dedicated-server product                                          |
| Modes                 | Classic + Deathmatch                                                                       | Competitive queue/lobby stack                                             |
| State                 | Explicit GameInstance/Match/Round ownership                                                | Global mutable gameplay state                                             |
| Persistence           | Delayed, versioned, non-atomic lobby snapshots                                             | Synchronous per-tick durability                                           |
| Recovery              | Schema ready for future takeover                                                           | Automatic host migration/failover in V1                                   |
| Gameplay feel         | Fast arcade, prediction, immediate presentation feedback                                   | Heavy realism / input waits for server RTT                                |
| Assets                | Migrate compatible existing models/rigs/animations                                         | Rebuild art/animation without need                                        |
