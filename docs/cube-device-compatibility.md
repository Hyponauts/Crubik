# Crubik cube device compatibility

This document describes which smart-cube protocols Crubik implements, how compatibility has been tested, and which devices are supported for release. It applies across all product stages. The [shared glossary](glossary.md) explains recurring technical terms.

## Compatibility test levels

- **Packet-tested:** Automated tests with fixed sample packets pass for decoding, encryption, cube-state conversion, and recovery. These tests alone do not prove that a real cube model works with Crubik.
- **Hardware-validated:** A real cube passes the checks below. The result applies to the tested model, firmware, operating system, and Crubik version.
- **Supported for release:** A hardware-validated combination is explicitly listed as supported in the compatibility table and meets the release requirements below.

Hardware validation is Crubik's own release check. It is not certification by a manufacturer, Bluetooth SIG, regulator, safety body, or other outside organization.

Finding a cube, pairing with it, or recognizing its Bluetooth service does not prove hardware compatibility. Passing packet tests is also not enough. A validated practice workflow does not mean orientation capture has been validated; the test record must explicitly include that feature.

## Current compatibility table

| Vendor/family | Protocols implemented for | Tests and results so far | Release support |
| --- | --- | --- | --- |
| GAN Gen2 | GAN Mini ui FreePlay, GAN12 ui/ui FreePlay, GAN356 i Carry/Carry S/i 3, and hardware using the same protocol service | Packet tests cover state, moves, packet sequence recovery, invalid-face gaps with preserved clock deltas, other invalid input, encryption, gyro availability, and `0x01` orientation and ODR-step rotation-speed decoding. Orientation capture has not been hardware-validated. | No hardware-validated combination documented |
| GAN Gen3 | GAN356 i Carry 2 protocol | Packet decoding and adapter tests. Hardware information explicitly reports that orientation is unavailable. | No hardware-validated combination documented |
| GAN Gen4 | GAN12 ui Maglev and GAN14 ui FreePlay protocols | Packet decoding, adapter, hardware-feature, and `0xEC` orientation and ODR-step rotation-speed tests. GAN12 ui Maglev practice was manually hardware-validated; orientation capture has not been separately hardware-validated. | GAN12 ui Maglev: Supported for release |
| MoYu AI 2023 | GAN Gen2-compatible packet format with MoYu encryption keys | Encryption and adapter tests. Orientation is available only if the cube reports the Gen2 hardware feature; the protocol family alone is not enough. | No hardware-validated combination documented |
| MoYu32 | `WCU_MY32` service: initial state, recovery of up to five moves, cube timestamps, and battery | Packet and adapter tests. Orientation is unavailable. MoYu32 practice was manually hardware-validated. | MoYu32 (`WCU_MY32`): Supported for release |

The table lists the models targeted by the implemented protocols and the tests completed so far. A model name in the protocol column does not mean the model is supported for release.

## Testing with a real cube

Each hardware-validation record must include:

- cube model and hardware revision, if these can be distinguished;
- firmware version;
- operating system, platform, and version;
- Crubik version or build ID;
- test date;
- observed results and known limitations.

A combination is hardware-validated only when its test record covers:

- discovery and first connection;
- reconnecting to a remembered cube;
- losing the connection and disconnecting normally;
- handling the initial cube state and a solved cube;
- every supported face and turn direction;
- mapping the reported state to the correct faces and cube orientation;
- packet order, sequence counters wrapping from their maximum value to zero, timestamps, and fast turns;
- recovering missed moves and correcting the app's state from a fresh cube-state report;
- cube sleep/wake and app background/foreground behavior;
- battery reporting where available;
- orientation capture, where available: stable quaternions, correct axes, consistent quaternion signs, feature detection, and continuous sample delivery;
- a long practice session representative of normal use.

Record failures, occasional problems, and platform-specific limits too. A pass on one firmware or operating system does not count as a pass on an untested combination.

## Release support status

A device combination may be marked **supported for release** only when:

1. Its exact model, firmware, platform, and Crubik version are hardware-validated.
2. No known limitation breaks the documented core practice workflow.
3. The supported-device documentation lists the tested combination and any limitations.
4. Automated protocol and connection tests still pass.
5. [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md) has up-to-date license information and credits for adapted protocol code.

Use the three status labels above exactly in support documentation. Do not describe packet-tested families as hardware-validated or supported for release.

## Adding or expanding device coverage

When adding a vendor, protocol family, model, firmware, or platform, test it to the level of support being claimed:

1. Review protocol sources and check that their licenses allow use in Crubik.
2. Add tests with fixed sample packets for initial state, live moves, encryption, invalid input, sequence counters and wrapping, missed-move recovery, state resynchronization, optional features, and any orientation or timing fields.
3. Decode vendor packets inside adapters and send common smart-cube events to the rest of the app.
4. Complete hardware validation for each combination that will be marked supported for release.
5. Update the compatibility table, architecture overview, tests, supported-device statements, and third-party notices wherever the change affects them.

A similar protocol does not mean another device is supported or planned for support.

## Reference material

- [Universal BLE](https://pub.dev/packages/universal_ble)
- [afedotov/gan-web-bluetooth](https://github.com/afedotov/gan-web-bluetooth)

Keep licenses and credits for adapted protocol code in [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
