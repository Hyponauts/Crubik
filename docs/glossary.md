# Crubik glossary

Shared terms used in the [architecture overview](architecture.md) and [cube device compatibility](cube-device-compatibility.md). Compatibility test levels and release requirements are defined in the compatibility document.

## Evidence and compatibility

| Term | Meaning |
| --- | --- |
| Evidence | Recorded facts that support a conclusion. For compatibility, these include automated test results and observations from real-cube tests. Recognizing a Bluetooth service alone does not prove hardware compatibility. For a solve, evidence includes received moves, states, orientation samples, timestamps, and known gaps. |
| Observation | One received event or sample. |
| Device combination | The exact cube model, firmware, operating-system platform and version, and Crubik version tested together. |
| Firmware | The software running inside the cube. |
| Authoritative state | The state used as the source of truth. For a connected cube, this is the cube-reported state; for saved practice data, it is the local database. |

## Device communication

| Term | Meaning |
| --- | --- |
| Protocol | The packet formats and commands Crubik uses to communicate with a cube. |
| Packet / fixture | A packet is a block of data sent by a cube. A fixture is fixed test data, such as a sample packet with an expected decoding result. |
| BLE / advertisement | BLE is Bluetooth Low Energy. An advertisement is a broadcast used to discover nearby devices before connecting. |
| Bluetooth service | A group of functions offered by a device, such as sending moves or reporting battery level. |
| Adapter / gateway | An adapter translates a vendor's packets into common app events. A gateway provides the app's interface for finding and connecting to devices. |
| Normalized event / vendor-neutral | A normalized event uses the app's common format for moves, states, orientation, features, or gaps. Vendor-neutral code can use that format without knowing which vendor sent the packet. |
| AES / MAC address | AES is the encryption algorithm used by the cube protocols. A MAC address is a device's Bluetooth address; some protocols use it when creating an encryption key. |
| Capability | A feature a cube reports or demonstrates, such as orientation sensing. |
| Data gap | A marker for missing or unreliable observations, so later analysis does not assume the recording is complete. |
| Recovery / resynchronization | Recovery retrieves missed moves. Resynchronization uses a fresh cube-state report to correct the app's view of the cube. |
| Sequence counter / rollover | A packet or move number used to track order and detect missing data. Rollover is when it reaches its maximum value and wraps to zero. |

## Orientation, timing, and practice

| Term | Meaning |
| --- | --- |
| Orientation / pose | How the whole cube is rotated in space, separate from turns of its faces. Pose samples record this orientation over time. |
| Quaternion | Four numbers used to describe a 3D orientation without relying on three separate rotation angles. Equivalent quaternions can have opposite signs; consistent signs avoid artificial jumps between samples. |
| Keyframe | An orientation sample kept for later replay or analysis. |
| ODR-step velocity | A rotation-speed value expressed per sensor sampling step. ODR means output data rate: how often the sensor produces a sample. |
| Monotonic clock | A clock that measures elapsed time without jumping when the system's date or time changes. |
| Host timestamp / cube timestamp | A host timestamp records when the app received data; it is not necessarily when the physical turn happened. A cube timestamp comes from the device's own clock. |
| Offset | A time relative to solve start. A negative offset means before the start. |
| Derived data / clock regression | Derived data is calculated from recorded observations, such as move intervals or turns per second (TPS). Clock regression estimates how the cube's clock relates to the host clock. It does not replace the original timestamps. |
| Ao5 | Average of five solves, calculated after dropping the fastest and slowest times. It is unavailable if any of those five solves has unavailable timing. |
| WCA random-state scramble | A competition scramble that targets a randomly selected puzzle state under World Cube Association rules. Crubik's local 20-move practice scrambles do not provide that guarantee. |

## Code structure and storage

| Term | Meaning |
| --- | --- |
| Domain model | A representation of a cube, move, solve, or other practice concept that does not depend on UI, Bluetooth, or database code. |
| Contract / interface | The operations and behavior a component promises to provide. Different implementations, including test fakes, can provide the same interface. |
| State machine / lifecycle | A state machine defines phases and allowed transitions, such as inspection to solving. A lifecycle covers how a component or recording starts, runs, and finishes. |
| Persistence / repository / Drift | Persistence saves data across app restarts. A repository provides access to saved records. Drift is the library used to work with Crubik's SQLite database. |
| Schema / migration / transaction | A schema defines database tables and fields. A migration updates an older database. A transaction saves related changes together: either all succeed or none do. |
| Serialization / lazy loading | Serializing operations means running them in order. Serializing data means converting it into a format such as JSON. Lazy loading means reading data only when it is needed. |
