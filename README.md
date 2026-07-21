# Crubik

Crubik is an offline-first Flutter companion for GAN and MoYu smart cubes. The
MVP keeps the complete practice loop on-device: connect a cube, follow a
scramble, watch turns update a live 3x3 model, time the solve, and retain the
session without an account or network connection.

## MVP capabilities

- Responsive phone, tablet, and desktop practice layouts.
- GAN Gen2, Gen3, and Gen4 BLE services, plus the MoYu AI 2023 Gen2 variant
  and the MoYu32 `WCU_MY32` protocol.
- MAC-salted AES packet decryption, initial facelet-state synchronization, and
  move-history recovery for supported protocols.
- A pure-Dart 54-sticker cube model, notation parser, and 20-move practice
  scramble generator.
- Touch and spacebar timing, move capture, automatic stop on a solved cube,
  best/mean/Ao5 statistics, and recent-solve deletion.
- Durable local solve storage through SQLite on native platforms and Drift's
  IndexedDB-backed storage on the web.
- Versioned JSON solve-history export through the clipboard.
- A hardware-free demo/manual-input path.

The current scramble generator is deliberately labelled a **practice
scramble**. A production WCA random-state generator remains a follow-up; its
pure-Dart implementation should be validated against TNoodle and cubing.js.

The current history schema exports solve summaries and timing/input metadata;
versioned persistence and export of the raw per-move event stream remains
Phase 0 work. Do not describe the current JSON as a lossless raw-event export.

## Cube scope

The P0 vendor scope is intentionally limited to GAN and MoYu:

- GAN Gen2: GAN Mini ui FreePlay, GAN12 ui / ui FreePlay, GAN356 i Carry / Carry
  S / i 3, and other hardware exposing the same packet-tested service.
- GAN Gen3: GAN356 i Carry 2 protocol.
- GAN Gen4: GAN12 ui Maglev and GAN14 ui FreePlay protocol.
- MoYu: MoYu AI 2023 using its GAN Gen2-compatible protocol and MoYu key
  material.
- MoYu32: `WCU_MY32` service with encrypted initial-state synchronization,
  five-move packet recovery, cube-relative timestamps, and battery reporting.

The adapters are implemented and packet-tested, including MoYu32, but every
marketed model/firmware/platform combination still needs physical-device
certification before a production compatibility promise is made.

## Run and verify

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

The generated Drift schema is committed. After changing the database tables,
regenerate it with:

```sh
dart run build_runner build
```

The web build includes `sqlite3.wasm` matching the locked `sqlite3` dependency
and a worker compiled from the locked Drift version.

## Product documentation

- [Product vision](docs/crubik-product-vision.md)

Third-party protocol attribution is documented in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
