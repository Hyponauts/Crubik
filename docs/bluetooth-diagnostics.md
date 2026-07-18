# Bluetooth cube diagnostics

Crubik records a small, local trace for the latest cube connection attempt. If
an attempt fails, use **Copy diagnostics** in the connection dialog and paste
the report into the development task. The report is designed to be useful to a
developer or AI agent without exposing a cube identifier or solve data.

The report includes the platform, selected protocol adapter, elapsed stage
times, service-match result, whether an encryption identity was available,
notification and write progress, packet length, decoded message category, and
the final failure category.

It deliberately omits:

- Bluetooth device IDs and MAC addresses;
- advertised names and manufacturer payloads;
- raw encrypted or decrypted packet bytes;
- facelet state, moves, timestamps, and solve history.

## Interpreting the last stage

| Last relevant stage | Likely layer to investigate |
| --- | --- |
| `ble.connect.started` | The operating-system BLE link did not complete. Check wake state, range, another app holding the cube, and platform permissions. |
| `ble.connect.succeeded` | The radio link worked; inspect service discovery next. |
| `gatt.discovery.succeeded ... protocolMatched=false` | The advertised device was recognized incorrectly or exposes a different protocol/service revision. |
| `protocol.identity.unavailable` | Crubik could not derive the MAC-based encryption key from native identity, manufacturer data, or the supported name pattern. |
| `notifications.subscribe.started` | GATT notification subscription failed or timed out. |
| `protocol.request.started` without matching `completed` | The characteristic write failed. |
| Requests completed with no `protocol.notification.received` | The cube ignored the handshake, another initialization command is required, or the firmware behaves differently. |
| `protocol.notification.received` followed by `protocol.message.rejected` | Packet length, MAC-derived key, cipher, or packet layout is wrong. |
| `protocol.message.decoded message=state` | Decryption and state decoding worked. |
| `protocol.handshake.succeeded` | The adapter is ready; later problems are in move delivery, state mapping, or reconnect handling. |

For `WCU_MY32`/WeiLong V10 AI, a healthy initialization trace should subscribe
to notifications, complete the `info`, `state`, and `battery` requests in that
order, decode a state message, and finish with `protocol.handshake.succeeded`.

Do not add production logging of identifiers or decrypted packet contents to
investigate a failure. If metadata is insufficient, use a separate,
developer-only capture with explicit user consent, a short capture window, and
manual review/redaction before sharing it.
