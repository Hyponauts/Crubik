# Crubik MVP Target

This document defines the scope and acceptance bar for Crubik's first releasable product. Its requirements describe the target regardless of whether an item is already implemented. Implementation progress belongs in tests, issues, and release tracking rather than in this document.

See the [product vision](crubik-product-vision.md) for enduring product direction, the [architecture overview](architecture.md) for implementation design, and [cube device compatibility](cube-device-compatibility.md) for protocol coverage and hardware support.

## MVP outcome

The MVP proves that Crubik can provide a dependable 3×3 practice loop without an account, backend, or network connection:

> A user can install Crubik, enable airplane mode, reconnect a previously approved cube, complete a long practice session, review every recorded solve, close and reopen the app, and lose no data.

## Definition of done

The MVP must provide:

- immediate local startup with no login, account, backend, or network gate;
- a hardware-free demo/manual workflow and a Bluetooth smart-cube workflow;
- locally generated 20-move practice scrambles;
- inspection, touch and spacebar timing, move capture, and automatic completion when a connected cube reports a solved state;
- a Flutter-native interactive 3D cube visualization;
- responsive, intentionally distinct mobile and desktop layouts;
- local solve history, best time, session mean, average of five, deletion, and versioned JSON export;
- SQLite persistence on native platforms and IndexedDB-backed Drift persistence on web;
- remembered-device startup scanning and automatic reconnect when the operating system has already granted Bluetooth access;
- normalized smart-cube state, move, battery, and connection events;
- packet-tested coverage for the selected GAN and MoYu protocol families;
- a documented set of cube combinations supported for release under the device compatibility policy.

## User experience requirements

### Quick start

The app must render the local practice workspace without waiting for network, authentication, history loading, or Bluetooth reconnect. History initialization and remembered-device discovery run asynchronously after the UI is created.

### Practice inputs

- Demo/manual mode must remain available without Bluetooth hardware.
- A new demo scramble initializes the rendered cube to the scrambled state.
- When a physical cube is connected, its authoritative state drives the live visualization; generating a scramble must not overwrite that state.
- A solve can finish from locally applied moves or a solved-state packet, and the recorded input source must preserve that distinction.

### Connection behavior

- Manual discovery shows identified cubes before unrelated BLE devices.
- Supported devices select a protocol adapter automatically.
- A successfully connected device is remembered locally.
- On the next native-app launch, Crubik scans for that exact device and connects without presenting another permission request when access already exists.
- Search, connection, success, failure, battery, and recovery states remain visible and actionable.
- The demo/manual route remains available when Bluetooth is unavailable, permission is missing, or a cube cannot connect.

### Local persistence

- Solve writes are serialized in completion order.
- Solves completed or deleted while history is loading are merged correctly.
- Pending writes are flushed before the owned database closes.
- Web persistence uses the version-matched Drift worker and SQLite Wasm artifacts committed to the repository.

## Hardware requirement

The MVP hardware scope is limited to selected GAN and MoYu protocol families. Current protocol coverage, evidence levels, validation records, and release support status are maintained in [Crubik cube device compatibility](cube-device-compatibility.md). Other vendors are outside this stage unless an approved product decision changes its scope.

## Puzzle and scramble target

The MVP supports the 3×3×3 practice workflow. The cube model must provide a 54-sticker representation, URFDLB notation, transformations, and Kociemba facelet interchange.

The local generator produces a 20-move **practice scramble** while avoiding immediate repeated faces and three consecutive moves on the same axis. It must not be described as competition-grade.

A future random-state generator requires an explicit implementation and licensing decision plus conformance testing against mainstream references such as TNoodle and cubing.js.

Other puzzles, WCA disciplines, Bluetooth timers, camera recognition, and competition workflows are outside the MVP.

## Data and portability target

The durable solve record must contain:

- a stable local identifier;
- scramble text;
- elapsed time and move count;
- UTC creation time;
- input source;
- inspection duration;
- solve-start trigger.

The JSON format must be versioned and preserve unknown input-source values without silently collapsing them. Persistence migrations must retain older solve records without inventing unavailable metadata.

The MVP export contains solve summaries and timing/input metadata. It does not promise a lossless raw move-event stream. Raw move-event persistence, device/firmware provenance, penalties, replay data, and analysis-engine versions require a compatible future schema extension.

Any future synchronization must use a durable, idempotent outbox over the local source of truth. Connectivity loss must remain irrelevant to capture and local review.

## Quality and release gates

Automated verification must cover:

- cube transformations and notation round trips;
- timer and practice-phase transitions;
- solve-history initialization, ordered writes, deletion, and migrations;
- responsive compact-phone and wide-desktop layouts;
- adapter recognition and initial-state handshake;
- fixed cipher vectors and encryption round trips;
- live moves, correct handing of the packet sequence, missed-move recovery, malformed packets, and state resynchronization;
- connection cancellation, permission failure, diagnostics redaction, and remembered reconnect.

End-to-end testing on real hardware must cover airplane mode, long sessions, fast turns, sleep/wake, background/foreground, disconnect/reconnect, and database close/reopen behavior on supported hardware.

The MVP is releasable only when the outcome at the start of this document is demonstrated on the supported release platforms and cube combinations documented as supported for release.

## Non-goals

- mandatory accounts, analytics, telemetry, or cloud services;
- a general social network, friend challenges, or leaderboards;
- compatibility claims for every smart cube;
- official WCA scramble or competition-system claims;
- lossless replay claims before raw move events are stored and exported;
- all WCA puzzles, blindfold workflows, camera recognition, or TV-specific games;
- a heavy game engine solely to animate the standard cube.

## Open decisions

1. Which platforms are included in the first release, and what Bluetooth support level must each meet?

## Change policy

Mentioning an idea, library, vendor, or protocol does not add it to the MVP. Only an approved product decision changes this target. When that happens, update scope, non-goals, release gates, tests, supported-device statements, and the architecture overview together wherever they are affected.

## Reference material

- [Flutter supported deployment platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Drift](https://drift.simonbinder.eu/)
- [TNoodle](https://github.com/thewca/tnoodle)
- [cubing.js](https://github.com/cubing/cubing.js)
- [WCA Regulations](https://www.worldcubeassociation.org/regulations/)

Protocol code adapted from third-party work retains its license and attribution requirements in `THIRD_PARTY_NOTICES.md`.
