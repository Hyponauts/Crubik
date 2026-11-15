# Crubik architecture overview

This document describes how Crubik's code is organized and how the app works while running.

Use it to understand which component handles each task, which parts depend on each other, and how data moves through the app. See [the product vision](crubik-product-vision.md) for long-term direction and [cube device compatibility](cube-device-compatibility.md) for implemented protocols, test results, and release support. The [shared glossary](glossary.md) explains recurring technical terms. When code changes affect this architecture, update the relevant text, tables, and Mermaid diagrams in the same change.

## Architectural goals

Crubik is an offline-first Flutter app. The full practice loop—input, scramble guidance, timing, visualization, history, statistics, and export—must work without an account, server, or network connection.

The code follows these rules to keep practice available offline:

- Application logic depends on interfaces defined by the app and domain models that do not need Flutter, Bluetooth, or a database. Widgets do not decode Bluetooth packets or decide solve rules.
- `PracticeController` alone controls practice phases and the timer.
- `CubeConnectionController` manages finding and connecting to physical cubes. Gateways and adapters handle vendor-specific details through common interfaces.
- `PracticeInputCoordinator` handles only actions and common cube events that involve both the practice and connection controllers. UI code reads each controller directly.
- The local database is the source of truth for saved data. Shared Drift code implements each feature's storage interfaces; feature logic does not use database-specific types.
- Smart-cube adapters send common move, state, orientation, capability, and data-gap events. Pairing or passing packet tests alone does not prove that a real cube works with Crubik.

## Code organization and dependency view

The code is split into UI (presentation), workflow coordination (application), models and rules (domain), device communication (transport/protocol), and saved data (persistence).

```mermaid
flowchart TB
    subgraph Presentation["Presentation"]
        Page["PracticePage"]
        Layouts["DesktopPracticeLayout / MobilePracticeLayout"]
        Widgets["Scramble, timer, session, connection, and 3D widgets"]
    end

    subgraph Application["Application"]
        Coordinator["PracticeInputCoordinator"]
        Practice["PracticeController"]
        History["SolveHistory"]
        Analyzer["SolveAnalyzer"]
        ScramblePool["ScrambleCache"]
        Connection["CubeConnectionController"]
        GatewayContract["CubeConnectionGateway / SmartCubeSession"]
        HistoryContract["SolveHistoryRepository"]
        SessionContract["PracticeSessionStore"]
        RememberedContract["RememberedCubeStore"]
        ScrambleStoreContract["ScrambleCacheStore"]
    end

    subgraph Domain["Pure Dart domain"]
        Cube["CubeMove / CubeAlgorithm / CubeState"]
        Scrambling["WcaScrambleGenerator / CubeSolver"]
        Device["CubeDeviceCandidate / Capabilities"]
        Events["Move / state / orientation / capability / gap events"]
        Solve["SolveRecord / SolveRecording / CountableSolve / SolveAnalysis / SolveAverage"]
        Method["PracticeSession / SolveMethodConfig / StateDescriptor"]
    end

    subgraph Infrastructure["Shared data and infrastructure"]
        BleGateway["BleCubeConnectionGateway"]
        Registry["CubeAdapterRegistry"]
        Adapters["GAN / MoYu adapters"]
        Protocols["Packet decoders and ciphers"]
        Central["BleCentral / UniversalBleCentral"]
        Repositories["Drift repositories"]
        Database["CrubikDatabase"]
        Cuber["CuberCubeSolver"]
        SolverRuntime["Native isolate / browser Worker"]
    end

    Page --> Layouts --> Widgets
    Page --> Coordinator
    Page --> Practice
    Page --> Connection
    Layouts --> Practice
    Layouts --> Connection
    Widgets --> Practice
    Widgets --> Connection
    Coordinator --> Practice
    Coordinator --> Connection
    Practice --> History
    Practice --> Analyzer
    Practice --> SessionContract
    Practice -. nextScramble callback .-> ScramblePool
    ScramblePool --> ScrambleStoreContract
    ScramblePool --> Scrambling
    Scrambling --> Cube
    History --> HistoryContract
    Practice --> Cube
    HistoryContract --> Solve
    Analyzer --> Solve
    Analyzer --> Method
    Connection --> GatewayContract
    Connection --> RememberedContract
    Connection --> Device
    Connection --> Events
    GatewayContract -. implemented by .-> BleGateway
    BleGateway --> Registry
    Registry --> Adapters
    Adapters --> Protocols
    Adapters --> Central
    Events --> Coordinator
    HistoryContract -. implemented by .-> Repositories
    SessionContract -. implemented by .-> Repositories
    RememberedContract -. implemented by .-> Repositories
    ScrambleStoreContract -. implemented by .-> Repositories
    Repositories --> Database
    Scrambling -. implemented by .-> Cuber
    Cuber --> SolverRuntime
```

The main source areas are:

| Area | Location | Purpose |
| --- | --- | --- |
| App setup | [`lib/app`](../lib/app) | Creates and owns the app's controllers, coordinators, and shared resources. |
| Shared infrastructure | [`lib/core`](../lib/core) | Storage code used by multiple features, a shared monotonic clock, and the app theme. |
| Cube domain | [`lib/features/cube/domain`](../lib/features/cube/domain) | Models for cubes, devices, features, events, and diagnostics, independent of Flutter and device APIs. |
| Cube application | [`lib/features/cube/application`](../lib/features/cube/application) | Connection management and app-defined interfaces for device communication and storage. |
| Cube data | [`lib/features/cube/data`](../lib/features/cube/data) | BLE access, adapter selection, vendor sessions, encryption, and packet decoding. |
| Practice domain | [`lib/features/practice/domain`](../lib/features/practice/domain) | Saved solve summaries, detailed recordings, timing calculations, and the storage interface. |
| Practice application | [`lib/features/practice/application`](../lib/features/practice/application) | Practice phases and transitions, input coordination, history, and statistics. |
| Practice presentation | [`lib/features/practice/presentation`](../lib/features/practice/presentation) | Responsive layouts, controls, history views, and cube rendering. |

## Main responsibilities

| Class or contract | Responsibility |
| --- | --- |
| `CrubikApp` | Creates and owns the controllers, shared database, monotonic clock, scramble cache and solver, and input coordinator. Starts history loading and reconnects to the remembered cube. Saves pending changes before closing its database. |
| `PracticePage` | Handles top-level navigation and chooses the layout for the screen width. Reads both controllers directly and uses the coordinator for actions involving both. Enables keyboard timing only on the active practice screen. |
| `DesktopPracticeLayout` / `MobilePracticeLayout` | Separate wide and compact layouts for preparation, attempts, solve review, and session history. Portrait preparation keeps the scramble and session summary around the expanding cube/review card. Wide preparation places scramble and summary on the left and cube/review on the right; short wide screens compact the scramble and place demo controls beside the cube. The Analyze destination owns history rather than duplicating it beside Practice. |
| `PracticeInputCoordinator` | Coordinates demo selection, connection changes, disconnect handling, and forwarding common cube events. These operations involve both controllers. UI code does not read state from the coordinator. |
| `PracticeController` | Controls the scramble, current cube state, inspection, timer, selected practice session, session-scoped statistics, when to start or stop recording, solve completion, review data, and preparation of the next scramble. It snapshots the selected session and method into each completed solve. On demand, it derives per-stage comparison means from the newest 100 solves after trimming the fastest and slowest 5% (rounded to whole solves for shorter history); skipped or unavailable stages are excluded. Expanded rolling averages load only their trimmed solve window and include stage data only from solves with the anchor's method snapshot. |
| `ScrambleCache` / `ScrambleCacheStore` | Maintains a sequential FIFO pool of ready scrambles behind a feature-owned persistence contract. Taking an item removes it before returning and then starts background refill; ready items remain available while the next item is generated, and an empty pool never substitutes a move-list fallback. |
| `SolveRecordingBuilder` | Builds an ordered event timeline with times relative to solve start. Keeps relevant pre-start observations, selects orientation samples to retain, detects clock jumps, and finishes the recording. Does not depend on practice phases, timers, or storage. |
| `CountableSolve` | Derives a face-turn-counted algorithm from observed moves without changing the recording. Adjacent equal quarter turns on one face become one half turn, while reversals remain distinct. Each counted move retains the raw move indices that supplied it, so stage timing still uses the original event timestamps. |
| `SolveHistory` | Owns the ordered solve collection, anchored Ao5/Ao12/Ao100 summaries, and persistence/export queue. It merges changes made while history loads, keeps failed writes for retry, loads detailed recordings and analysis only when needed, and produces versioned JSON. A new solve computes one entry per full rolling window; deletion updates only newer overlapping anchors. Deleting an entire session removes its records and averages in one pass and schedules one repository operation without recalculating unrelated sessions. |
| `SolveAverageWindow` / `SolveAverageRecord` | Pure rolling-window rules and persisted summary. Ao5/Ao12 trim one fastest and one slowest; Ao100 trims five of each. DNF and DNS sort as worst and produce a DNF average when their count exceeds the worst trim. An unobserved time remains unavailable, not DNF. Average times use truncated centisecond attempts and nearest-centisecond average rounding. A reconstructed window also identifies its best/worst excluded members for the Solves tab without duplicating them in storage. |
| `SolveStatistics` | Shared pure aggregation for single-solve comparison columns and expanded Ao details. Stage breakdowns use only complete, current analyses with the anchor's method; whole-solve turns and TPS use all retained window members. Each metric averages only its available values; missing recognition, execution, TPS, or regrip data is not counted as zero. Aggregate TPS is the arithmetic mean of each included solve's TPS, not total turns divided by total time. |
| `PracticeSession` / `PracticeSessionStore` | A named local history scope with its current solve-method configuration. The Drift implementation stores the small session list and selected ID in app settings. Deleting a session explicitly deletes its solves. |
| `SolveMethodConfig` / `StateDescriptor` | Method presets and the method-agnostic predicates used to recognize stage boundaries from cube states. CFOP descriptors recognize Cross, four cumulative F2L-pair milestones, and last-layer milestones; Layer by Layer uses layer milestones. Custom methods store an ordered subset. Stages use method names such as EOLL, COLL, CPLL, EPLL, OLL, and PLL; `Solved` is not a selectable stage. Legacy saved `solved` identifiers load as PLL. |
| `SolveAnalyzer` | Replays the countable moves derived from an immutable recording, compares white- and yellow-Cross progress when the session does not fix a Cross face, and recognizes the first achievement of each configured stage in method order. The final configured stage closes only when its predicate and the fully solved cube state are both reached. Later algorithms may temporarily break earlier completed stages without moving their boundaries. It derives recognition time, execution time, cumulative time, turns, TPS over the full step time (including recognition), skipped stages, and orientation-based regrips. Regrips are distinct orientation-change episodes with settling hysteresis rather than accumulated sensor motion. A telemetry gap makes analysis explicitly unavailable rather than guessed. |
| `SolveRecord` | Saved solve summary and immutable context snapshot: outcome, timing availability, move count, input source, inspection duration, start trigger, session ID/name, and solve method. |
| `SolveRecording` | Versioned timeline in a common format across vendors. Contains observed moves, cube-reported states, selected orientation samples, data gaps, available host and cube times, and protocol features. Times between moves are calculated later, not stored. |
| `SolveAnalysis` | Versioned derived data stored separately from its authoritative recording. An analyzer-version mismatch triggers lazy reanalysis when the solve is opened. |
| `CubeConnectionController` | Manages discovery, permissions, scan cancellation, startup reconnect, sessions, battery state, diagnostics with private data removed, and common cube events. For a connected GAN session, it requests a hardware facelet-state reset only after explicit user confirmation and waits for a solved-state report; a successful BLE write alone is not considered confirmation. |
| `CubeConnectionGateway` | App-defined interface for finding and connecting to cubes. The app uses a BLE implementation, while application logic stays independent of the BLE plugin. |
| `SmartCubeSession` | Common interface for a cube connection: startup confirmed by a cube-state report, state requests, events, battery, connection status, and cleanup. |
| `ResettableSmartCubeSession` | Optional capability for sessions that can reset the cube's internal facelet state to solved. GAN Gen2–4 implement the capability; other vendors do not expose it without protocol evidence. |
| `BleCubeConnectionGateway` | Uses the adapter registry to identify BLE advertisements, then asks the selected adapter to connect. |
| `BleCentral` / `UniversalBleCentral` | BLE interface that can be replaced in tests, and its `universal_ble` implementation. |
| `CubeAdapterRegistry` | Checks device recognizers in order, classifies support, supplies protocol names for display, and selects adapters. |
| `SmartCubeAdapter` | Interface for recognizing devices and creating sessions for one protocol. |
| `BleSmartCubeSession` | Shared event subscription, startup, and cleanup for encrypted BLE cube sessions. |
| `InitialStateHandshake` | Waits for an actual cube-state report before marking a connection ready. Records failure diagnostics with private data removed. |
| GAN adapters and protocol classes | Handle GAN Gen2–4 and MoYu AI 2023: service selection, AES encryption using the MAC address as salt, state and move decoding, missed-move recovery, optional hardware-feature requests, and Gen2/Gen4 orientation decoding. A Gen3/Gen4 state awaiting missing move history gets two minutes to recover; if history never arrives, the adapter emits a recovery-timeout gap and the pending state. Only an active solve receiving that timeout becomes DNF. |
| MoYu32 adapters and protocol classes | Handle device identity, encryption, state, moves, battery, recovery of up to five moves, timestamps, and state resynchronization. |
| `CubeMove`, `CubeAlgorithm`, `CubeScramble`, and `CubeState` | Pure 3×3 notation and transformation model shared by protocols, practice logic, scrambling, and visualization. `CubeAlgorithm` owns the common immutable move sequence and notation; `CubeScramble` gives it solved-to-target semantics. `CubeState.fromCubieCoordinates` is the common validation and conversion boundary for generated and device-reported cubie states. |
| `CubeSolver` / `CubeSolution` | Solver abstraction returning a target-to-solved `CubeAlgorithm`. `CubeSolution.toScramble()` reverses and inverts that sequence for scramble generation. The abstraction is independent of the two-phase implementation so later training solvers can provide different strategies without changing consumers. |
| `WcaScrambleGenerator` | Uniformly samples reachable 3×3 cubie states, applies TNoodle's default distance filter, solves target-to-solved, and inverts the solution into a scramble. |
| `CuberCubeSolver` | Adapts the local `cuber` two-phase solver with the same 21-move search bound configured by TNoodle for 3×3, a 60-second attempt timeout, and one retry against the same target. The bound is a maximum accepted solution length, not a minimum scramble length. Search runs in an isolate on native platforms and a generated dedicated Worker on web. |
| `CrubikDatabase` | Shared Drift database structure and migrations for solve summaries, anchored rolling averages, gzip-compressed raw recording JSON blobs, versioned analysis JSON, and app settings. |
| `DriftSolveHistoryRepository` | Saves a solve summary, optional compressed recording, and new average entries in one transaction. Loads summaries separately and detailed evidence on demand. Deleting a solve updates only its overlapping average windows in the same transaction and cascades to its recording and analysis. |
| `encodeSolveRecording` / `decodeSolveRecording` | Persistence-owned codec for lossless gzip-compressed UTF-8 recording JSON. Uses the pinned `archive` package on native and web platforms; keeps compression outside the domain model and export format. |
| `DriftRememberedCubeStore` | Saves the most recently connected device ID and display name. |
| `DriftScrambleCacheStore` | Stores the expendable versioned scramble pool as an application setting without adding a schema table. |
| `Cube3DView` | Draws the 3D cube in Flutter, handles interaction and move animation, and respects reduced-motion settings. |

## Smart-cube connection and event flow

`CubeConnectionController` starts listening for session events, battery updates, and connection status before calling `SmartCubeSession.start()`. Startup completes only after the adapter is listening for notifications and `InitialStateHandshake` receives a cube-state report. Listening first prevents the app from missing the initial state.

```mermaid
sequenceDiagram
    participant App as CrubikApp
    participant CC as CubeConnectionController
    participant Store as RememberedCubeStore
    participant GW as BleCubeConnectionGateway
    participant Reg as CubeAdapterRegistry
    participant Adapter as SmartCubeAdapter
    participant Session as BleSmartCubeSession
    participant Clock as MonotonicClock
    participant Coordinator as PracticeInputCoordinator
    participant Practice as PracticeController
    participant Builder as SolveRecordingBuilder

    App->>CC: reconnectRememberedCube()
    CC->>Store: load()
    Store-->>CC: device id and name
    CC->>GW: startScan()
    GW->>Reg: identify(advertisement)
    Reg-->>GW: CubeDeviceCandidate
    GW-->>CC: scan result
    CC->>GW: connect(candidate)
    GW->>Reg: adapterFor(candidate)
    Reg-->>GW: GAN or MoYu adapter
    GW->>Adapter: connect(BleCentral, candidate)
    Adapter-->>GW: SmartCubeSession
    GW-->>CC: SmartCubeSession
    CC->>Session: subscribe to events, battery, and link
    CC->>Session: start()
    Session->>Session: subscribe, request state, decrypt, decode
    Session->>Clock: stamp notification receipt
    Session-->>CC: SmartCubeStateEvent
    CC-->>Coordinator: authoritative state
    Coordinator->>Practice: activate smart-cube mode and sync state
    Session-->>CC: startup completes
    CC->>CC: mark connection ready
    Session-->>CC: normalized move / state / pose / gap events
    CC-->>Coordinator: normalized events
    Coordinator->>Practice: forward complete event metadata
    Practice->>Practice: advance flow and classify lifecycle gaps
    Practice->>Builder: start / record observation / finish
```

The same path handles live moves, state resynchronization, orientation samples, data gaps, and solve completion.

### Event timing and recording

The BLE session and practice controller share one monotonic clock owned by the app. Before decoding, each notification gets a host timestamp: the time the app received it. All moves recovered from that notification share that receipt time and stay in decoder order.

Receipt times can go backwards in the event timeline when GAN returns recovered moves before a live packet that was received earlier and held in a buffer. Crubik keeps the original timestamps. GAN Gen3/4 holds a state report that is ahead of the last applied move until the requested move history has been replayed; an incomplete history response emits a real data gap before applying that state. Recovery and state-request BLE writes are serialized so adjacent packet callbacks cannot reorder them. If the solve duration cannot be determined, it marks timing unavailable rather than counting the solve as a zero-time personal best. Stored host times are offsets from solve start, not absolute clock values.

`PracticeController` decides when a recording starts, finishes, or is discarded. It also checks whether a cube-reported state change proves that some moves were missed. The controller records the solved state before finishing the recording and classifies disconnects according to the practice phase. Aborting an attempt discards its unfinished timeline.

`SolveRecordingBuilder` puts retained observations in sequence, translates protocol data-gap events, and detects cube-clock resets. MoYu sessions send gap events before the affected recovered moves, so a move that completes the solve cannot cause the gap to be lost. GAN Gen2 decoding marks an invalid face as a missing observation while retaining its reported clock delta. The gap makes the interval across that omitted move unavailable; later consecutive moves can still use the cube clock.

The builder keeps orientation samples using these rules:

- Keep the latest sample from before solve start as the starting orientation for replay. Its time offset is negative because it came before the solve.
- Keep an orientation keyframe at each move, state, or gap boundary.
- Keep the first and final orientation samples, and both samples around a change of at least one degree.
- Normalize quaternions to unit length and align their signs before saving them.

### Orientation support and privacy

GAN Gen2 `0x01` and Gen4 `0xEC` packets become common orientation events. Decoding follows the packet layouts in the pinned upstream version, including signed quaternion components and optional rotation-speed values per sensor sampling step (ODR-step angular velocity).

Hardware-information requests are optional during startup. Gen2 reports a gyro flag; Gen4 reports a model name. GAN Gen3 and MoYu32 do not invent orientation support or samples. `SolveRecordingBuilder` records whether the cube reported orientation support or actually sent orientation samples.

Vendor packets, decrypted data, device IDs, advertised names, signal strength (RSSI), and battery values must not enter solve recordings or production diagnostics that have not been redacted.

The adapter registry currently selects packet-tested adapters for GAN Gen2–4, MoYu AI 2023, and MoYu32. Implementing a protocol, validating real hardware, and supporting it for release are separate claims. See [cube device compatibility](cube-device-compatibility.md) for the current results and hardware test requirements.

## Practice lifecycle

`PracticeController` is the single owner of the timer and practice state machine. Scramble acquisition may be asynchronous: while the initial or next item is being prepared, timing actions remain disabled and presentation shows progress; a generation error can be retried. When replacing an existing scramble, the previous move sequence remains visually stable and non-actionable; the progress overlay appears only when preparation outlasts a brief cache-hit grace period. Manual/demo input becomes ready with the rendered cube initialized to the completed scramble target. Smart-cube input preserves authoritative physical state while a scramble is being prepared and never overwrites that state merely because a new scramble was generated.

The diagram is a user-flow view. `PreparingScramble`, `InputSelection`, and `Review` are conceptual states rather than `PracticePhase` enum values. Review is represented by `pendingSolveReview`; after completion, preparation of the next scramble begins immediately and the review can remain visible while that asynchronous work completes.

```mermaid
stateDiagram-v2
    [*] --> PreparingScramble
    PreparingScramble --> InputSelection: scramble ready
    PreparingScramble --> PreparingScramble: retry after failure
    InputSelection --> ManualReady: choose demo
    InputSelection --> AwaitingCubeState: connect smart cube
    AwaitingCubeState --> Scrambling: authoritative solved state
    AwaitingCubeState --> NeedsSolvedCube: authoritative unsolved state
    NeedsSolvedCube --> Scrambling: cube becomes solved
    Scrambling --> InspectionDelay: target scramble reached
    ManualReady --> InspectionDelay: start
    InspectionDelay --> Inspection: readiness delay expires
    Inspection --> Solving: first move or inspection timeout
    Solving --> Review: complete and request next scramble
    Review --> ManualReady: next ready in demo mode
    Review --> Scrambling: next ready with solved smart cube
    Review --> NeedsSolvedCube: next ready with unsolved smart cube
    Review --> AwaitingCubeState: smart cube disconnects
    InspectionDelay --> ManualReady: abort demo attempt
    Inspection --> ManualReady: abort demo attempt
    Solving --> ManualReady: abort demo attempt
```

For smart-cube attempts, aborting or dismissing review returns to `AwaitingCubeState`, `Scrambling`, or `NeedsSolvedCube`. The choice depends on whether the cube has reported its state and whether it is solved. A solve can finish either when a state packet reports a solved cube or when applying received moves produces a solved state. Keep both completion paths working.

The selected session can change only outside an active attempt; solve review does not block session settings. Completion stores the session ID, its display name, and the current method on the solve before the next scramble is requested. Later edits to a session therefore do not change the historical context shown in the solve's Info tab. Practice shows Last/Best Single, Ao5, Ao12, and Ao100 for the selected session. Analyze has Single/Ao5/Ao12/Ao100 history tabs. At most one row is expanded within the selected tab; the Single row keeps the shared analysis tabs without duplicating its summary, while an average row loads trimmed stage means on demand. Overview and TPS charts share stage-column layout, axes, grid, labels, tooltips, and legend styling. Recognition occupies the bottom of stacked Overview bars and execution the top. The Single TPS view compares each stage with the newest 100 usable analyses. Average rows also have a Solves tab showing their exact window, best/worst trimmed members, and links that switch to and focus the corresponding Single row. Analyze retains each expanded average, its inner tab, and its scroll position while moving between Single and average tabs; leaving Analyze for Practice resets that view state. Deleting a current or historical solve always requires explicit confirmation. A successful manual cube selection closes its connection dialog even when its content has rebuilt into the connected state.

## Persistence and offline behavior

The shared database and concrete persistence adapters live under `lib/core/data` because the database serves practice history, remembered cube state, and the ready-scramble pool. Feature code continues to depend on feature-owned repository and store contracts.

```mermaid
flowchart LR
    Practice["PracticeController"] --> History["SolveHistory"]
    Practice --> SessionStore["DriftPracticeSessionStore"]
    Practice --> Analyzer["SolveAnalyzer"]
    History -->|serialized add / delete| SolveRepo["DriftSolveHistoryRepository"]
    Connection["CubeConnectionController"] --> Remembered["DriftRememberedCubeStore"]
    Cache["ScrambleCache"] --> ScrambleStore["DriftScrambleCacheStore"]
    SolveRepo --> DB["CrubikDatabase"]
    SessionStore --> DB
    Remembered --> DB
    DB --> Summaries["solve_entries"]
    DB --> Recordings["solve_recordings: gzip-compressed JSON BLOB"]
    DB --> Analyses["solve_analyses: versioned JSON"]
    DB --> Averages["solve_averages: anchored Ao results"]
    DB --> Settings["app_settings: sessions and selected ID"]
    ScrambleStore --> DB
    DB --> Native["SQLite on native platforms"]
    DB --> Web["SQLite Wasm + IndexedDB on web"]
    History -->|lazy loadRecording| SolveRepo
    History -->|lazy loadAnalysis| SolveRepo
    History --> Export["Crubik JSON v5"]
```

### Saving and loading

- Local data is the source of truth. Recording and review work without a network connection.
- `SolveHistory` runs writes and exports in order. Failed writes stay queued and are retried on later changes, an explicit save of pending changes (flush), or export. Each operation captures its write sequence boundary when requested, so an earlier retry cannot save mutations queued after an export. Export captures its summaries and timestamp immediately, merges history still loading with the local changes captured at that point, and keeps later writes behind its recording reads. Export fails if an earlier write still has not been saved.
- A smart-cube summary and its versioned raw recording JSON are saved in one transaction. Recording JSON is compact UTF-8, losslessly gzip-compressed into the `solve_recordings.payload` BLOB column without base64 encoding. The same codec works on native platforms and web. Each solve has at most one recording row, with explicit event sequence numbers. Deleting the solve also deletes its recording. Times between moves are calculated during export, not stored in the recording.
- New solve summaries store the countable face-turn total for TURNS and overall TPS; recording events remain unmodified. Older summaries retain their original move totals because recordings are loaded only on demand and manual solves may have no move recording. Opening an older smart-cube solve rebuilds its versioned stage analysis with the countable sequence and uses that result for displayed total TURNS/TPS, without rewriting the stored summary.
- Derived analysis is saved in `solve_analyses` with its analyzer version and JSON payload. It is disposable: missing, damaged, or older analysis can be rebuilt lazily from the recording. The raw recording remains authoritative and is never rewritten by analysis.
- `solve_averages` contains only kind, anchor solve ID, session ID, timestamp, result status, and rounded time. It does not store an overlapping list of all member IDs or duplicate stage analyses. The ordered solves reconstruct at most 100 members when one result is expanded. Initial migration/backfill rebuilds missing entries once; normal startup validates anchors without recalculating values. A deletion removes the deleted solve's anchored entry (if present) and recalculates only later entries whose windows included that solve; if the deleted solve was among the first attempts, the oldest newly incomplete window disappears instead. For a session with enough solves, each average history loses exactly one entry.
- Session settings and solve changes share one persistence queue. Deleting a session saves the updated session list and selection and deletes its solves and averages in the same Drift transaction; recordings and analyses cascade from the solves. Other sessions' averages are unchanged. Replacing an average after a solve deletion refreshes any open breakdown, even if the anchor is unchanged.
- Loading a recording validates its gzip checksum and uncompressed size before decoding JSON. Damaged or unsupported recordings fail the read and export rather than silently discarding evidence.
- Startup loads solve summaries and the small session-settings document only. Detailed event timelines and analysis load when a solve is opened or exported. Opening Overview can lazily load or rebuild at most the newest 100 analyses from that solve's session for stage comparisons, so longer sessions still do not load every move and orientation sample into memory.
- Solves added or deleted while history loads are merged with the loaded data.
- `CrubikApp` saves pending history changes before closing its database.
- The scramble pool is expendable, contains at most fifteen plain scramble strings, and is refilled one item at a time without blocking access to ready entries or waiting for persistence on the cache-hit path. Corrupt or unavailable cache data is ignored; failure to generate when the pool is empty is surfaced to practice UI.

### Database and generated files

Native platforms use Drift with SQLite. Web uses SQLite WebAssembly (`sqlite3.wasm`) and a Drift worker (`drift_worker.dart.js`), with data saved in IndexedDB. `build_runner` generates these ignored, version-matched files. The asset downloader fetches the pinned WASM release and verifies it before saving the file. A clean build needs network access; the deployed app includes everything it needs.

When the Drift schema changes, regenerate ignored `*.g.dart` files locally with `build_runner`. Add a migration and migration tests when `schemaVersion` increases. Before Flutter web builds, `build_runner` also downloads SQLite WASM and compiles the Drift and cube-solver workers. Never commit generated Dart files or web runtime output.

Schema version 4 added gzip-compressed JSON recording storage and solve timing reliability. Schema version 5 adds the session/method snapshot columns and the separate `solve_analyses` table. Schema version 6 adds the solve outcome and `solve_averages` table. Schema version 7 indexes average anchor IDs so deleting a session does not scan unrelated average histories for every cascading solve deletion. Upgrading from versions 1–6 preserves solve summaries, inspection metadata, recordings, and remembered-cube settings. Older solves are assigned to the default SpeedSolving session with CFOP, but no recording or analysis is invented; rolling averages are derived from their existing summaries once.

### Export and timing reliability

Crubik JSON version 5 includes each solve's outcome and session/method snapshot, the anchored average history, plus nested recording and analysis values only when they exist. Summary timing is unavailable if the first or final move was recovered, a state report establishes an unobserved start or finish, or the finish receipt time is earlier than solve start. State-based completion still saves the solve and its recording, including after reconnect, but does not substitute the report's receipt time for an unknown physical boundary. A gap or state correction in the middle of a solve does not invalidate otherwise observed boundaries. Unavailable timing exports as `timing_reliable: false` and `elapsed_ms: null`.

Review and history display “Timing unavailable” for these solves. Best and mean exclude them. An Ao window with an unobserved completed time remains unavailable rather than silently classifying it as DNF or using a fabricated time. DNF/DNS outcomes are represented in saved data and average rules; controls to assign these outcomes are outside the current practice UI.

SQLite keeps the original clock values inside the compressed recording. Export decompresses each recording on demand and emits readable, uncompressed JSON with calculated move intervals and the clock used for each interval. The first move's time from solve start is a separate value from its “time since previous move,” which is always unavailable because there is no previous move.

Analyze exports only the solves and averages of the session selected when the action starts, including if the user switches sessions while the Android picker is open. On Android, Analyze opens the system document picker first, then streams the JSON to an app-cache file and copies it into the selected document. Android supplies the app-cache directory after the picker returns so Dart writes to the same directory that native code validates, even if Flutter's system temp directory is different. Canceling the picker avoids preparing a potentially large export. Only paths, not the JSON, cross the platform channel. The temporary file is removed after saving or failure; on failure Android also attempts to remove the incomplete document in the background without delaying the error shown to the user. Other platforms currently copy the session JSON to the clipboard.

### What a recording keeps

Recordings keep quarter-turn order, sequence numbers (serials), recovery flags, actual cube timestamps where available, cube-reported states, selected orientation samples, feature availability, and explicit data gaps.

They do not keep duplicate time differences, state snapshots for every move, encrypted or decrypted packets, device identity, signal strength, battery values, or animation frames. Derived TPS, pauses, method stages, and regrips are calculated from the recording. Case recognition, replay, and clock regression remain future derived consumers of the same evidence.

## Extension points

When adding a smart-cube protocol:

1. Use `SmartCubeAdapter` for device recognition and session creation.
2. In `CubeAdapterRegistry`, register supported adapters before recognizers that only detect devices.
3. Convert packets into common smart-cube events before sending them to application logic. Include reported features and data gaps.
4. Timestamp receipt with the shared monotonic clock. Preserve timestamps, move/state sequence numbers, recovered-move order, cube-reported states, and diagnostics with private data removed.
5. Clearly mark unavailable sensor or timing data. Never invent orientation or cube-clock values from host timing.
6. Add repeatable tests for packets, encryption, startup, recovery, invalid input, features, and the connection controller. Validate real hardware separately.

When changing the practice flow, put phase transitions and timing rules in `PracticeController`. UI code handles layout and interaction. Use `PracticeInputCoordinator` only for behavior involving both practice and the physical connection.

When changing scramble generation, keep reachable-state sampling in `WcaScrambleGenerator`, solver strategy behind `CubeSolver`, platform execution behind the Cuber backend, and prefetch/persistence policy in `ScrambleCache`. WCA-style output is not an official WCA competition-system claim.

When changing saved data, update the feature's record and storage interface first. Then update Drift and the versioned export format. Preserve original recorded data and keep older data readable.

## Keeping this document current

Update this document whenever a code change affects:

- which component handles a task or a public app interface;
- which parts depend on each other or how features are separated;
- cube discovery, connection, initial-state handshake, or common event flow;
- practice phases, timer control, input changes, or solve completion;
- storage responsibilities, database structure, startup loading, saving pending changes, or export;
- ways to extend the app or supported protocol families.

Update explanations, tables, and affected diagrams together. Remove old names; do not document aliases that the code does not provide.
