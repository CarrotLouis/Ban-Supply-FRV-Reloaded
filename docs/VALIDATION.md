# Validation and acceptance boundary

Date: 2026-10-14 (Asia/Shanghai). Candidate: **0.1.1-vanilla-lease.1**.
No game launch or live-manager change was made for this fix.

## Confirmed defect in 0.1.0

The user reported that an unmodded teammate driving the protected FRV did not
restore gun resupply. Existing addon logs contain
`held: ownership transferred before reload restoration` on 2026-10-12.
The old implementation cleared the replicated enabled bits but depended on the
old owner observing the pending-transfer window and restoring them first. Once
authority had moved, the native property queue would not publish that old
client's changes. Increasing polling frequency cannot guarantee catching this.
The offline negative control also demonstrates that a disabled mask with no
delayed-enable bits remains disabled on an unmodded new owner.

## 0.1.1 implementation

Only M-103 resource `9b2140378640432e` is eligible. Runtime zero-based zones 5 and
6 are VehicleWeaponResupply (type 21). The checked seven-zone layout is
`19,19,9,19,19,21,21`. Other seat, supply and weapon state is not modified.
The resource, entity ID and engine unit generation identify an instance;
its network unit is resolved afresh and excluded from the stable tracking key.
All memory addresses are resolved on each action, including timer cleanup after
native manager compaction. Raw addresses are never kept in tickets or baselines.

The relevant per-instance flags and local runtime data are:

| Field | Location | Behavior |
| --- | --- | --- |
| Enabled mask | flags +0 | Native property `788B9753` |
| Delayed-enable mask | flags +4 | Native property `99901914` |
| Other disable flag | flags +8 | Preserved |
| Global disable/lock | flags +12 | Preserved |
| Zone's delayed-enable timer | instance +zone*0x68 +0x5C | Local float32; not in the flags payload |

When protecting the vehicle, actual addon Lua holds only the two local timers
at finite float32 `1e20`, arms the replicated delayed-enable bits `0x60`, then
clears the same two enabled bits using the native setter. Ordinary frame deltas
round to no timer change, so an empty owned car needs no timer-refresh writes.
The stable state makes zero setters, property notifications or memory writes.

The new unmodified owner retains its own ordinary timers. The native timer
update sees the pending bits, enables both zones and clears those bits. This
requires no Lua execution on the new owner, and no pre-transfer observation or
post-transfer write from the old owner. An enabled mod owner instead renews the
lease; an OFF mod owner also explicitly enables the zones and removes our bits.
The old mod owner resets only its local held timers after losing authority,
even when no new driver avatar was observed. It does not write remote flags.

An OFF toggle while on foot keeps the existing per-car protection. Empty cars,
passenger entry and cancelled driver entry retain protection while the old
authority remains. Each unrelated vehicle remains untouched. Checked-write or
read-back failure releases held timers so a partial disable can recover using
the already-armed native bits. The original game global disable remains in
effect; this mod does not override a vehicle disabled by the game itself.

## Native evidence and build guard

The retained Steam-25480438 capture and the currently installed files match:

- EXE SHA256: `F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06`
- game.dll SHA256: `2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E`

Both hashes gate runtime initialization. Five native fingerprints are also
checked before any action: setter `+978610`, property queue `+FD97E0`, timer
update `+977FA0`, flags receiver `+980020`, and initializer `+977650`.
The setter ABI is `(manager*, entity_id u32, zone u32, enabled uint8)`.
The property queue takes `(network_unit u32, property u32, field_pointer*)`.
The initializer's actual copy at `+97786F` / `+977879` places the definition
zone's StartEnabledDelay (zone +0x30) into the local timer (runtime +0x5C).
Both gun-resupply definitions contain `-1.0f`.
The actual receiver writes the four flags fields and never imports held timers.

There is no executable patch, hook, ownership request, custom network protocol,
whole-process scan, shared-template edit, helper DLL or custom key binding.
The three shared runtime source files retain the locked upstream hashes.
Writes use its private, committed, writable-data checks. The native code and
raw game definitions are externally supplied evidence and are never exported.

## Offline results

80 explicit LuaJIT checks pass: menu 6, native boundary 31, policy 27 and guarded
reader 16. They cover per-car persistence, OFF while parked, unobserved control
transfer, inherited OFF restoration, remote-ON ownership, repeated acquisition,
network-ID changes, generation replacement, relocated timers, unknown layouts,
write failures, unrelated flags and fingerprint mismatch. Real Win32 tests also
verify the canonical private aliases on this offline process's own buffers,
including rejection of module-image writes and file SHA256.

`tests/verify_native_lease.py` executes actual addon Lua on LuaJIT 2.1 against
separate Unicorn peer memory, invoking actual captured setter, receiver and
timer-update instructions. Its 13 cases include:

- Actual native timer initialization and the legacy failure negative control.
- 2400 native frames of protection without refresh writes or notifications.
- Received flags preserve the unmodded peer's local timers; unowned peers wait.
- An unmodded new owner restores both zones with **zero Lua on either side of
  the handoff**, even when the old owner completely misses the transfer.
- Local-only old-owner cleanup and OFF reacquisition.
- ON -> ON -> unmodded transfer, installed-but-OFF transfer, and five repeated
  transfers back to the same unmodded peer.
- Unrelated enabled and delayed bits are preserved through recovery.

The downstream property queue is intercepted in these instruction tests, and
the resulting flags payload is delivered through the actual native receiver.
This proves the captured instructions and addon control flow under the supplied
peer state. It does **not** prove live transport, engine callback timing,
in-game startup stability or real multiplayer behavior.

All modules and the exact assembled entry compile on LuaJIT 2.1. The exact
entry verifies default-ON registration, singleton and lossless update chaining.
Actual ModOptionsMenu public API source accepts the toggle and applied ON/OFF
values. The canonical 17 FFI private declarations and dynamic bindings pass
the adapted audit; the generic skill scanner cannot parse upstream's computed
private names and `ffi.cdef(DECLARATIONS)`, so it is not used as a false success.

The official loader builder and independent skill inspector validate the ZIP's
envelope, stable GUID, resource and exact bundled source. The isolated Arsenal
0.36.2 backend fixture imports, deploys and purges the candidate, with exactly
three unchanged-hash addon payloads and no live profile changes. This is backend
evidence, not a claim that the user-facing manager UI was exercised.

## Remaining live acceptance

0.1.1 is a test candidate. Live native execution, MODS rendering for this addon,
real delivery to teammates, post-exit/death persistence, and normal driver
migration as both host and guest require actual game verification. Disabled
grey prompts may remain; removal of UI hints for unmodded peers is not provided.
Host migration or authority changes without a new driver were not tested.

Minimum sequence: ON driver protects A; leave A empty; an unmodded teammate
drives A and BOTH sides become usable; repeat with an installed-but-OFF driver;
then an ON driver takes over and both sides become blocked again. Repeat as
guest/host and with two cars, passenger/gunner entry, death, OFF on foot,
OFF while driving, and repeated swaps. Check another client's ability to use
gun resupply, not solely the old controller's local grey prompt.
