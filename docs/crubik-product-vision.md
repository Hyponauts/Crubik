# Crubik Product Vision

This document defines why Crubik exists, the experience it should grow toward, and the principles every release must preserve. It deliberately does not define the scope or completion status of a particular development stage.

Release targets and implementation status are intentionally maintained outside this vision. The code structure that supports the product is described in [the architecture overview](architecture.md).

## Mission

Crubik makes smart-cube practice feel as immediate and dependable as picking up a physical timer:

> A cuber can connect, scramble, solve, understand, and retain a practice session without surrendering access to an account, vendor, or internet connection.

Crubik brings timing, live cube state, solve history, and useful feedback into one trustworthy practice workspace. Hardware and platform differences stay behind the experience, while the user keeps control of the practice record.

## Who Crubik serves

Crubik is for cubers who want their regular practice to be captured accurately without adding setup friction. It must remain useful to someone with a supported smart cube and to someone practicing with an ordinary cube.

The product is especially valuable when it:

- shortens the distance between picking up a cube and beginning a solve;
- makes physical turns visible and understandable without distracting from practice;
- preserves a dependable personal record across long practice sessions;
- helps a cuber learn from evidence instead of opaque or vendor-locked metrics;
- works predictably when Bluetooth, a platform service, or the network is unavailable.

## Product promise

Crubik should become a durable, vendor-neutral home for cube practice. A user should be able to move between supported cubes and platforms without losing the ability to practice locally, understand past solves, or export their data.

The product may grow from reliable capture into deeper analysis, coaching, more puzzles, broader hardware support, and optional connected experiences. Those capabilities are valuable only when they strengthen the practice workflow and do not weaken its offline reliability, clarity, privacy, or data ownership.

## Product principles

1. **Offline is the default.** The complete core practice loop works locally.
2. **No account before value.** Authentication or connectivity never gates a local practice session.
3. **Local data is authoritative.** Network loss or a future service outage cannot block, discard, or silently rewrite a solve.
4. **Practice comes before configuration.** Startup, reconnection, and input selection minimize the time between opening Crubik and turning the cube.
5. **Hardware differences stay behind the experience.** Product features consume stable, vendor-neutral behavior rather than expose protocol details.
6. **Protocol coverage is not hardware validation.** Packet-tested protocol code does not establish compatibility with a marketed cube. Hardware support status must be explicitly documented.
7. **Evidence is preserved.** Raw inputs are not silently replaced by derived metrics as persistence and analysis evolve.
8. **Data remains portable.** Versioned export formats evolve compatibly and retain enough provenance to interpret older records.
9. **Privacy is the default.** Diagnostics and practice data stay local and redacted unless the user explicitly chooses to share them.
10. **Expansion earns its place.** New vendors, puzzles, analysis, and connected features must improve the practice experience without destabilizing the trusted core.

## Enduring experience contract

### Immediate local value

The practice workspace is available without waiting for authentication, network access, synchronization, or optional services. Background initialization must not prevent a user from starting a local practice session.

### Flexible practice input

A hardware-free route remains a first-class experience. When a supported physical cube is connected, its reported state is authoritative for the live experience. Switching inputs must be explicit, recoverable, and understandable.

### Transparent hardware behavior

Discovery, connection, reconnect, battery, recovery, and failure states remain visible and actionable. Unsupported hardware is explained honestly rather than appearing to connect unreliably.

### Trustworthy records

A completed solve is retained locally before any optional network action. History remains available after restart, and data can be exported in a documented, versioned format. New analysis should preserve the evidence needed to reproduce or reinterpret its conclusions.

### Accessible interaction

The product supports touch, keyboard, scalable text, reduced motion, adequate contrast, and non-color-only status cues. Compact and wide layouts are designed for their available space instead of stretching a single composition.

## Product pillars

### Dependable practice

Scramble guidance, inspection, timing, move capture, visualization, review, and history form one coherent loop. Each part should make the next action obvious and keep timing behavior predictable.

### Trustworthy hardware bridge

Crubik normalizes supported smart-cube behavior into one product experience. Protocol research and packet-level support are steps toward compatibility, not substitutes for real-hardware evidence.

### User-owned practice record

The local record is the foundation for statistics, replay, comparison, and future coaching. Schema and export evolution must retain provenance and remain compatible with older data.

### Useful understanding

Analysis should help a cuber decide what to practice next. Derived metrics must be explainable, tied to captured evidence, and clearly distinguished from raw facts.

### Optional connection

Synchronization, sharing, aggregate analytics, and social experiences may be added later, but only as optional layers over the local source of truth. Loss of connectivity must remain irrelevant to capture and local review.

## Hardware and puzzle strategy

Crubik expands hardware support deliberately. A shared protocol or successful pairing does not imply that every marketed model is supported.

The product begins with focused 3×3 practice and may expand to other puzzles or competition workflows when the core is reliable and the new experience has a clear user benefit. Practice scrambles and competition-grade random-state scrambles must always be labelled according to the guarantees they actually provide.

Current protocol coverage, validation evidence, and release support status are maintained in [Crubik cube device compatibility](cube-device-compatibility.md).

## Evolution strategy

Crubik evolves in deliberate layers:

1. Establish a trustworthy offline practice foundation.
2. Add adjacent practice capabilities that deepen learning without weakening capture or data integrity.
3. Introduce optional connected experiences over the local source of truth.
4. Explore broader puzzles, inputs, and coaching only when they can remain isolated from the dependable core.

An idea, library, vendor, or protocol reference is not a product commitment. Only an approved product decision changes the current delivery target.

## Measures of success

Crubik is succeeding when:

- a user can begin useful practice quickly and without an account;
- long offline sessions retain every completed solve;
- connection and recovery behavior is understandable rather than mysterious;
- release support status matches documented hardware-validation evidence;
- users can export and continue to interpret their practice history;
- new capabilities make practice more useful without making the core less dependable.
