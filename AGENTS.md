# Crubik contributor guide

This file applies to the entire repository. It contains contributor procedures and constraints that are not already maintained in the project documentation.

## Required project context

- Treat `docs/crubik-product-vision.md` as the source of truth for the product mission, long-term direction, and enduring product principles.
- Treat `docs/cube-device-compatibility.md` as the source of truth for protocol coverage, compatibility evidence, physical-device compatibility validation, and release support status.
- Treat `docs/architecture.md` as the source of truth for current code structure, component responsibilities, dependency boundaries, runtime flows, state behavior, persistence invariants, and extension guidance.
- Read the relevant project documentation before changing product behavior, device coverage, or architecture. Do not expand the requested scope implicitly.

## Code conventions

### Human-readable Dart

- Let `dart format` control Dart indentation and expression layout. Do not manually align columns, insert line breaks solely to satisfy a preferred width, or fight the formatter. For prose and other non-formatted files, rely on the IDE's soft wrapping rather than storing manual line wraps.
- Use a blank line between conceptual stages such as validation, preparation, transformation, side effects, and return. Keep tightly related statements together; do not add a blank line after every statement.
- In tests, separate arrange, act, and assert with whitespace when it improves the reading flow. Do not add comments that merely label those stages.
- Use domain-specific names that reveal intent. Prefer verbs for operations, nouns for values and types, plural names for collections, and `is`, `has`, `can`, or `should` prefixes for booleans. Include units in names when they are otherwise ambiguous, such as `timeoutSeconds` or `elapsedMilliseconds`.
- Short names such as `index`, `row`, or `face` are appropriate in small scopes. Preserve established protocol acronyms such as GAN, BLE, AES, and MAC, but do not invent abbreviations merely to shorten names.
- Prefer type inference when an initializer makes the static type obvious. For local variables, use `final` when the binding is not reassigned, `var` when it is reassigned, and `const` for compile-time constants. Write a complete explicit type instead of `var`, or alongside `final` or `const`, when the declaration has no initializer, the inferred type is non-obvious, incomplete, `dynamic`, or different from the intended contract, or an API boundary needs a stable documented type. State the intended static type, using an appropriate interface rather than unnecessarily exposing a concrete implementation, and do not repeat a type already evident from a literal, typed collection, constructor, or well-known typed call.
- Keep a function at one level of abstraction, prefer guard clauses when they reduce nesting, and localize mutation. Extract a helper when its name captures a meaningful operation or separates a responsibility; do not split code only to satisfy an arbitrary line-count limit.
- Apply SOLID principles pragmatically. Keep classes and functions cohesive, extend behavior through the existing contracts and adapter boundaries, preserve substitutability in implementations and fakes, keep interfaces narrow, and depend on application-owned abstractions rather than infrastructure details. Do not add an interface, wrapper, or dependency-injection layer unless it creates a real boundary, variation point, or testing benefit.
- Comments explain information the code cannot express: protocol provenance or vendor quirks, packet offsets, lifecycle and concurrency ordering, privacy or redaction constraints, non-obvious mathematics, and why a simpler-looking implementation would be incorrect. Keep such comments close to the invariant.
- Do not add comments that narrate statements, repeat names, explain ordinary Dart syntax, label obvious sections, preserve deleted code, or compensate for unclear naming. Remove stale comments when behavior changes.
- Add Dartdoc to public contracts when callers need behavioral guarantees, ownership or lifecycle rules, failure behavior, or other non-obvious context. Do not require documentation for every self-explanatory constructor, getter, private helper, or data field.

## Protocol attribution and privacy

Protocol constants and behavior are adapted from the MIT-licensed `afedotov/gan-web-bluetooth` project at commit `65173e2cdd0fa38ef384f237f6da8d76c177ed1e`. Preserve attribution in `THIRD_PARTY_NOTICES.md` when modifying or redistributing that work. Never log device identifiers, MAC addresses, decrypted packets, or solve history in production diagnostics without explicit user consent and appropriate redaction.

## Generated artifacts

Generated Dart source and the web runtime files are local build output
and must not be committed. After `flutter pub get`, after changing Drift tables,
migrations, DAOs, or either worker entrypoint, and after changing locked web
database dependencies, run:

```sh
dart run build_runner build
```

Platform plugin registrants, `*.g.dart` files, `web/drift_worker.dart.js`,
`web/cube_solver_worker.dart.js`, and `web/sqlite3.wasm` are generated; do not
hand edit or commit them. `build_runner` compiles the database and cube-solver
worker entrypoints and materializes them under `web/` for Flutter's web tooling.
It also downloads the
pinned, version-matched `web/sqlite3.wasm` payload and verifies its checksum. A
clean build therefore requires network access; the resulting static deployment
remains self-contained.

## UI and accessibility expectations

- Check at least a compact phone viewport and a wide desktop viewport after UI changes. Verify scrolling, dialogs, keyboard focus, long text, and no render overflow.
- Keep touch and spacebar timing usable. New keyboard shortcuts must not steal input from dialogs or editable controls.
- Use semantic labels, scalable text, adequate contrast, and non-color-only status cues. Avoid making animation required to understand solve state.

## Development workflow

Use the Flutter/Dart versions compatible with `pubspec.yaml` and respect `pubspec.lock`. Dependency upgrades require checking all native targets.

Typical setup and verification:

```sh
flutter pub get
dart run build_runner build
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
- Do not commit generated build output such as `build/`, `*.g.dart`, `web/drift_worker.dart.js`, `web/cube_solver_worker.dart.js`, or `web/sqlite3.wasm`.
- For dependency or protocol code copied or adapted from another project, confirm license compatibility and update third-party notices in the same change.
