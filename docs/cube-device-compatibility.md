# Crubik cube device compatibility

This document is the source of truth for smart-cube protocol coverage, compatibility evidence, physical-device compatibility validation, and release support status. It is independent of any particular product stage.

## Compatibility evidence levels

- **Packet-tested:** Protocol parsing, encryption, state conversion, and recovery behavior pass deterministic fixtures. This does not establish compatibility with a marketed cube on real hardware.
- **Hardware-validated:** A specific marketed cube model, firmware version, operating-system platform, and Crubik version pass the physical-device compatibility checks in this document.
- **Supported for release:** Crubik may assign this status only to hardware-validated combinations explicitly listed as supported in the compatibility matrix.

Physical-device compatibility validation is an internal Crubik release process. It is not legal, safety, regulatory, manufacturer, Bluetooth SIG, or other third-party certification.

Discovery, successful pairing, a shared service, or packet-tested protocol code does not by itself move a device beyond packet-tested status.

## Current compatibility matrix

| Vendor/family | Intended protocol coverage | Current evidence | Release support |
| --- | --- | --- | --- |
| GAN Gen2 | GAN Mini ui FreePlay, GAN12 ui/ui FreePlay, GAN356 i Carry/Carry S/i 3, and hardware exposing the same protocol service | Packet-tested fixtures for state, moves, packet sequence recovery, malformed input, and encryption | No hardware-validated combination documented |
| GAN Gen3 | GAN356 i Carry 2 protocol | Packet decoding and adapter tests | No hardware-validated combination documented |
| GAN Gen4 | GAN12 ui Maglev and GAN14 ui FreePlay protocols | Packet decoding and adapter tests; GAN12 ui Maglev manually hardware-validated | GAN12 ui Maglev: Supported for release |
| MoYu AI 2023 | GAN Gen2-compatible packet format with MoYu key material | Encryption and adapter fixtures | No hardware-validated combination documented |
| MoYu32 | `WCU_MY32` service, including initial state, five-move recovery, cube timestamps, and battery | Packet and adapter fixtures; MoYu32 manually hardware-validated | MoYu32 (`WCU_MY32`): Supported for release |

The matrix describes implemented protocol intent and available evidence. Model names in the protocol-coverage column do not establish supported-for-release status.

## Physical-device compatibility validation

Each validation record must identify:

- marketed cube model and hardware revision where distinguishable;
- firmware version;
- operating system, platform, and version;
- Crubik version or build identifier;
- test date;
- observed results and known limitations.

A combination becomes hardware-validated only when recorded evidence covers:

- discovery and first connection;
- remembered reconnect;
- link loss and clean disconnect;
- initial and solved-state handling;
- every supported face and turn direction;
- state mapping and orientation;
- packet ordering, sequence-counter rollover from its maximum value back to zero, timestamps, and fast turns;
- missed-move recovery and state resynchronization;
- sleep/wake and background/foreground behavior;
- battery reporting where available;
- a representative long practice session.

Failures, intermittent results, and platform-specific limitations remain part of the validation record. Passing on one firmware or operating system must not be generalized to untested combinations.

## Release support status

A device combination may be marked **supported for release** only when:

1. Its exact model, firmware, platform, and Crubik version are hardware-validated.
2. No known limitation breaks the documented core practice workflow.
3. The supported-device documentation names the validated combination and any limitations.
4. Automated protocol and connection tests remain green.
5. Required protocol attribution and licensing are current in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

Support documentation must use the evidence labels exactly. Packet-tested families must not be presented as hardware-validated or supported for release.

## Adding or expanding device coverage

A new vendor, protocol family, marketed model, firmware, or platform requires evidence appropriate to the claim:

1. Review protocol sources and license compatibility.
2. Add deterministic fixtures for initial state, live moves, encryption, malformed input, packet sequence counters and rollover, recovery, and resynchronization.
3. Keep vendor packets behind the adapter boundary and publish normalized smart-cube events.
4. Complete physical-device compatibility validation for each combination intended to be marked supported for release.
5. Update the compatibility matrix, architecture overview, tests, supported-device statements, and third-party notices together where affected.

Protocol similarity does not implicitly schedule or support another device.

## Reference material

- [Universal BLE](https://pub.dev/packages/universal_ble)
- [afedotov/gan-web-bluetooth](https://github.com/afedotov/gan-web-bluetooth)

Protocol code adapted from third-party work retains its license and attribution requirements in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
