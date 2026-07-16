# Crubik contributor guide

This file applies to the entire repository. It captures the product and
engineering constraints that future automated contributors should preserve.

## Product mission and current scope

Crubik is an offline-first Flutter companion for Bluetooth smart Rubik's
cubes. The complete practice loop must work without an account, backend, or
network connection: connect or use demo/manual input, receive a scramble,
visualize turns, time a solve, and retain the result locally. Online sync,
aggregate analytics, social features, and content updates are optional future
extensions; they must not gate local practice.

The current MVP is a 3x3 practice application. Treat
`docs/crubik-product-vision.md` as the single source of truth for product scope,
priorities, supported-hardware plans, and architecture direction. Priorities
are ordered P0 through P3, with P0 most urgent. Do not pull later-tier work into
the MVP unless a request explicitly changes scope, and keep the vision document
aligned whenever an approved decision changes the product direction.

## Non-negotiable product rules

- Keep the core capture, timer, visualization, statistics, history, and export
  flows fully functional offline.
- P0 smart-cube discovery and support are limited to GAN and MoYu. Do not add
  Monster Go, GoCube, Giiker, QiYi, or other vendors to P0 implicitly, even if a
  protocol appears compatible.
- A protocol implementation or successful pairing is not hardware
  certification. Describe current adapters as packet-tested until the exact
  cube model, firmware, operating system, state mapping, fast turns, recovery,
  and reconnect behavior have been tested with physical hardware.
- The current generator produces a 20-move **practice scramble**, not a WCA
  random-state scramble. Keep that distinction visible. A production Dart
  scrambler should be validated against mainstream implementations such as
  TNoodle and cubing.js before its output is called competition-grade.
- Local data is authoritative. A future backend may synchronize or aggregate
  it, but network loss must never interrupt or discard a solve.
- Keep user data portable. Extend the versioned, lossless Crubik JSON format
  compatibly; do not silently remove fields or overwrite raw evidence with
  derived metrics.

## Architecture map

- `lib/main.dart`: application entry point.
- `lib/app/crubik_app.dart`: composition root; owns controllers/database and
  forwards normalized smart-cube move and state streams to practice state.
- `lib/features/cube/domain/cube_model.dart`: pure-Dart 54-sticker 3x3 model,
  URFDLB notation, transformations, and Kociemba facelet interchange.
- `lib/features/cube/domain/scramble_generator.dart`: local practice scrambles.
- `lib/features/cube/domain/smart_cube_device.dart` and
  `smart_cube_event.dart`: vendor-neutral discovery, capability, connection,
  move, and state models.
- `lib/features/cube/data/gan_cube_protocol.dart`: GAN Gen2-4 and MoYu AI 2023
  encryption, packet decoding, state conversion, and missed-move recovery.
- `lib/features/cube/data/adapters/`: device recognition and protocol-specific
  smart-cube sessions, selected through `CubeAdapterRegistry`.
- `lib/features/cube/data/ble/ble_central.dart` and
  `cube_connection_gateway.dart`: BLE plugin boundary and adapter orchestration.
- `lib/features/cube/application/cube_connection_controller.dart`: discovery,
  connection lifecycle, demo mode, and normalized event delivery to the UI.
- `lib/features/practice/application/practice_controller.dart`: timer, live
  cube state, solve lifecycle, statistics, JSON export, and serialized writes.
- `lib/features/practice/data/crubik_database.dart`: Drift schema and local
  solve repository.
- `lib/features/practice/presentation/practice_page.dart`: responsive practice
  experience; widths of 900 px and above use the desktop layout.
- `lib/features/practice/presentation/widgets/isometric_cube.dart`: cube
  renderer.
- `test/features/`: domain, BLE/protocol, controller, and persistence tests.
- `test/widget_test.dart`: responsive MVP flow and integration widget tests.

Keep domain logic and vendor packet parsing out of widgets. Product features
should consume normalized `SmartCubeMoveEvent` and `SmartCubeStateEvent`
objects instead of raw BLE packets. Hide vendor differences behind transport
and protocol adapters.

## Important state behavior

- In manual/demo mode, a new scramble initializes the rendered cube to the
  scrambled state.
- With a real smart cube connected, the physical cube's reported state is the
  source for the live visualization; generating a scramble must not overwrite
  it with a simulated state.
- A solve may finish from a solved state packet as well as from locally applied
  moves. Preserve both paths and their input-source metadata.
- Persist writes in order and flush pending writes before closing the database.
- Keep timestamps and state/move serial information intact when extending
  protocol handling; recovery logic depends on ordering.

## Bluetooth and supported hardware

The implemented protocol targets are:

- GAN Gen2: GAN Mini ui FreePlay, GAN12 ui/ui FreePlay, GAN356 i Carry/Carry
  S/i 3, and hardware exposing the same verified service.
- GAN Gen3: GAN356 i Carry 2 protocol.
- GAN Gen4: GAN12 ui Maglev and GAN14 ui FreePlay protocol.
- MoYu AI 2023 using its GAN Gen2-compatible packet format and MoYu key.

Protocol constants and behavior are adapted from the MIT-licensed
`afedotov/gan-web-bluetooth` project at commit
`65173e2cdd0fa38ef384f237f6da8d76c177ed1e`. Preserve attribution in
`THIRD_PARTY_NOTICES.md` when modifying or redistributing that work. Never log
device identifiers, MAC addresses, decrypted packets, or solve history in
production diagnostics without explicit user consent and appropriate
redaction.

When changing a protocol, add deterministic packet fixtures covering initial
state, live moves, wraparound/serial behavior, missed-move recovery, malformed
input, and encryption round trips. Hardware-specific claims still require
physical-device testing after packet tests pass.

## Local persistence and generated artifacts

Native targets use SQLite through Drift. Web uses Drift with IndexedDB-backed
storage and requires both `web/sqlite3.wasm` and
`web/drift_worker.dart.js`. These artifacts must match the versions resolved in
`pubspec.lock`; do not upgrade Drift/sqlite3 or replace only one web artifact
in isolation.

`lib/features/practice/data/crubik_database.g.dart` is generated and committed.
After changing Drift tables, migrations, or DAOs, run:

```sh
dart run build_runner build
```

Review generated changes and add migration tests when increasing
`schemaVersion`. Platform plugin registrants are Flutter-generated; do not hand
edit them unless a platform tool explicitly requires it.

## UI and accessibility expectations

- Preserve intentionally distinct mobile and desktop compositions; do not
  merely stretch the phone interface across a desktop window.
- Check at least a compact phone viewport and a wide desktop viewport after UI
  changes. Verify scrolling, dialogs, keyboard focus, long text, and no render
  overflow.
- Keep touch and spacebar timing usable. New keyboard shortcuts must not steal
  input from dialogs or editable controls.
- Use semantic labels, scalable text, adequate contrast, and non-color-only
  status cues. Avoid making animation required to understand solve state.
- The demo/manual path is a supported hardware-free workflow and must remain
  available for development, tests, and users with an ordinary cube.

## Development workflow

Use the Flutter/Dart versions compatible with `pubspec.yaml` and respect
`pubspec.lock`. Dependency upgrades require checking all native targets and the
version-coupled Drift web assets.

Typical setup and verification:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

Run focused tests during iteration, then the full analyzer and test suite
before handing off. A change to cube transformations, packet decoding,
persistence, timer state, or responsive layout requires a regression test at
the corresponding layer. Do not weaken an assertion just to make a failing
test pass.

Native builds have additional local prerequisites: Android requires a
configured Android SDK, and Apple builds require Xcode/CocoaPods. Report a
missing toolchain separately from a source or test failure.

## Change discipline

- Read the product vision and relevant tests before widening scope.
- Preserve unrelated user changes in a dirty worktree.
- Keep implementation, tests, documentation, supported-device statements, and
  `THIRD_PARTY_NOTICES.md` aligned.
- Do not add mandatory analytics, sign-in, telemetry, or cloud services to an
  offline feature.
- Do not commit generated build output such as `build/`; only commit generated
  source/runtime artifacts already called out above when their inputs change.
- For dependency or protocol code copied or adapted from another project,
  confirm license compatibility and update third-party notices in the same
  change.
