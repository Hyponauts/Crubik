# Crubik

Crubik is an offline-first Flutter companion for Bluetooth smart cubes. The MVP keeps the complete practice loop on-device: connect a cube, follow a scramble, watch turns update a live 3x3 model, time the solve, and retain the session without an account or network connection.

## MVP capabilities

- Responsive phone, tablet, and desktop practice layouts.
- Smart-cube protocol adapters for the packet-tested families documented in [Crubik cube device compatibility](docs/cube-device-compatibility.md).
- MAC-salted AES packet decryption, initial facelet-state synchronization, and move-history recovery for supported protocols.
- A pure-Dart 54-sticker cube model, notation parser, and 20-move practice scramble generator.
- Touch and spacebar timing, move capture, automatic stop on a solved cube, best/mean/Ao5 statistics, and recent-solve deletion.
- Durable local solve storage through SQLite on native platforms and Drift's IndexedDB-backed storage on the web.
- Versioned JSON solve-history export through the clipboard.
- A hardware-free demo/manual-input path.

The current scramble generator is deliberately labelled a **practice scramble**. A production WCA random-state generator remains a follow-up; its pure-Dart implementation should be validated against TNoodle and cubing.js.

The current history schema exports solve summaries and timing/input metadata; versioned persistence and export of the raw per-move event stream remains future work. Do not describe the current JSON as a lossless raw-event export.

## Cube device compatibility

Current protocol coverage, compatibility evidence, physical-device compatibility validation, and release support status are maintained in [Crubik cube device compatibility](docs/cube-device-compatibility.md). Packet-tested adapters must not be described as supported for release without the required real-hardware evidence.

## Run and verify

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

The generated Drift schema is committed. After changing the database tables, regenerate it with:

```sh
dart run build_runner build
```

The web build includes `sqlite3.wasm` matching the locked `sqlite3` dependency and a worker compiled from the locked Drift version.

## Product documentation

- [Product vision](docs/crubik-product-vision.md)
- [Cube device compatibility](docs/cube-device-compatibility.md)
- [Architecture overview](docs/architecture.md)

Third-party protocol attribution is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
