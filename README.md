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
dart run build_runner build
flutter run
flutter analyze
flutter test
```

Generated Drift Dart source is intentionally excluded from Git. Generate it
after dependency setup and whenever database tables, migrations, or DAOs change:

```sh
dart run build_runner build
```

For active schema work, `dart run build_runner watch` keeps the local source
current.

The web build includes two committed runtime payloads because a static/offline
deployment loads them directly:

- `web/drift_worker.dart.js` is compiled from `web/drift_worker.dart` with
  `dart compile js -O4 web/drift_worker.dart -o web/drift_worker.dart.js`.
- `web/sqlite3.wasm` comes from the upstream release matching the locked
  `sqlite3` package (`2.9.4`). Its SHA-256 checksum is
  `922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117`.

When either dependency changes, regenerate or download the matching payload,
update the checksum above, build the web app, and test database startup in a
browser before committing the runtime artifact.

## Product documentation

- [Product vision](docs/crubik-product-vision.md)
- [Cube device compatibility](docs/cube-device-compatibility.md)
- [Architecture overview](docs/architecture.md)

Third-party protocol attribution is documented in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
