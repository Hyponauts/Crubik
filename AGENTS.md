# Crubik contributor guide

This file applies to the entire repository. It contains contributor procedures and constraints that are not already maintained in the project documentation.

## Required project context

- Treat `docs/crubik-product-vision.md` as the source of truth for the product mission, long-term direction, and enduring product principles.
- Treat `docs/cube-device-compatibility.md` as the source of truth for protocol coverage, compatibility evidence, physical-device compatibility validation, and release support status.
- Treat `docs/architecture.md` as the source of truth for current code structure, component responsibilities, dependency boundaries, runtime flows, state behavior, persistence invariants, and extension guidance.
- Read the relevant project documentation before changing product behavior, device coverage, or architecture. Do not expand the requested scope implicitly.

## Protocol attribution and privacy

Protocol constants and behavior are adapted from the MIT-licensed `afedotov/gan-web-bluetooth` project at commit `65173e2cdd0fa38ef384f237f6da8d76c177ed1e`. Preserve attribution in `THIRD_PARTY_NOTICES.md` when modifying or redistributing that work. Never log device identifiers, MAC addresses, decrypted packets, or solve history in production diagnostics without explicit user consent and appropriate redaction.

## Generated artifacts

Generated Dart source is local build output and must not be committed. After
`flutter pub get`, and after changing Drift tables, migrations, or DAOs, run:

```sh
dart run build_runner build
```

Platform plugin registrants and `*.g.dart` files are generated; do not hand edit
them. Version-matched web runtime payloads such as `web/sqlite3.wasm` and
`web/drift_worker.dart.js` remain committed because static deployments load them
directly.

## UI and accessibility expectations

- Check at least a compact phone viewport and a wide desktop viewport after UI changes. Verify scrolling, dialogs, keyboard focus, long text, and no render overflow.
- Keep touch and spacebar timing usable. New keyboard shortcuts must not steal input from dialogs or editable controls.
- Use semantic labels, scalable text, adequate contrast, and non-color-only status cues. Avoid making animation required to understand solve state.

## Development workflow

Use the Flutter/Dart versions compatible with `pubspec.yaml` and respect `pubspec.lock`. Dependency upgrades require checking all native targets.

Typical setup and verification:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web
```

Run focused tests during iteration, then the full analyzer and test suite before handing off. A change to cube transformations, packet decoding, persistence, timer state, or responsive layout requires a regression test at the corresponding layer. Do not weaken an assertion just to make a failing test pass.

Native builds have additional local prerequisites: Android requires a configured Android SDK, and Apple builds require Xcode/CocoaPods. Report a missing toolchain separately from a source or test failure.

## Change discipline

- Preserve unrelated user changes in a dirty worktree.
- Keep implementation, tests, documentation, supported-device statements, and `THIRD_PARTY_NOTICES.md` aligned.
- Follow the maintenance criteria in `docs/architecture.md` and update its explanations, tables, and diagrams in the same change whenever they are affected.
- Keep the product vision aligned whenever an approved decision changes product direction.
- Keep the cube device compatibility document aligned whenever protocol coverage, validation evidence, or release support changes.
- Do not commit generated build output such as `build/` or `*.g.dart`. Commit only the generated runtime artifacts explicitly called out above when their inputs change.
- For dependency or protocol code copied or adapted from another project, confirm license compatibility and update third-party notices in the same change.
