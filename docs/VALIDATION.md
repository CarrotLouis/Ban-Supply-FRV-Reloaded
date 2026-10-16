# Validation and acceptance boundary

Date: 2026-10-17 (Asia/Shanghai). Candidate: **0.2.0-callin.1**.
No game launch or live-manager change was made for this fix.

## 0.2.0 call-in activation

The added trigger observes the vanilla transport component at `game+3326518`.
Only its owned prefix (+0x10) has the local 0x40-byte state at +0x40; remote
copies must not be read through that local-state array. A transport's resource
must be `75be82ed8592a6b3`, its cargo resource must be the exact M-103 resource,
and the cargo entity from state +8 must independently resolve as that vehicle.

The caller member is an **avatar entity ID** at transport state +0x18. It is
not a Player entity, a roster index or the transport's present network owner.
The dispatcher copies spawn-context +0x3A4 to +0x3E8 (`+6AC025` / `+6AC02B`),
transport creation copies it into +0x18 (`+6D98E5` / `+6D98FC`), and actual cargo
creation records its returned entity ID into +8 (`+6D9326`). Native +606520 maps
an avatar to its Player by resolving each roster slot's avatar network ID, also
confirming that the two entity classes must not be conflated.

The reader matches the full local session peer at `user+B398` to roster peers
at `player+2C8+slot*38`, then resolves that slot's avatar at +3A8+slot*20.
It keeps only full generational avatar IDs already proven local in the same
scene/peer. This lets a call finish after death or respawn without attributing
an unrelated actor's vehicle to the caller. History is committed only after
the complete read guards pass, and cleared on scene/session changes.

Each native transport snapshots the applied toggle when first observed before
its cargo is ready. A delivery is consumed once after successful activation;
its metadata cannot reapply the ban after an inactive new driver restores it.
An initial snapshot of already-delivered cargo is a baseline, not a new call.
An OFF call is not replayed by turning ON later, while an ON-started transport
retains its eligibility if the caller turns OFF on foot during delivery.
No shared definition, spawn request or owner is modified. The first consistent
10-Hz observation where cargo and interactions are ready applies protection;
there is no seat-entry prerequisite. Live delivery latency remains unmeasured.

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

Both hashes gate runtime initialization. Eight native fingerprints are also
checked before any action: three caller/cargo copy regions above, setter `+978610`, property queue `+FD97E0`, timer
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

123 explicit LuaJIT checks pass: menu 6, native boundary 31, policy 27, call-in
policy 24 and guarded reader 35. They cover per-car persistence, OFF while parked, unobserved control
transfer, inherited OFF restoration, remote-ON ownership, repeated acquisition,
network-ID changes, generation replacement, relocated timers, unknown layouts,
write failures, unrelated flags and fingerprint mismatch. Real Win32 tests also
verify the canonical private aliases on this offline process's own buffers,
including rejection of module-image writes and file SHA256.

`tests/verify_native_lease.py` executes actual addon Lua on LuaJIT 2.1 against
separate Unicorn peer memory, invoking actual captured setter, receiver and
timer-update instructions. Its 16 cases include:

- Actual native timer initialization and the legacy failure negative control.
- Actual native caller-avatar and cargo-entity copy instructions, protection
  without any driver through actual policy/Lua, and native unmodded recovery
  of a vehicle originally protected by the call-in trigger.
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

0.2.0 is a test candidate. Live native execution, MODS rendering for this addon,
real delivery to teammates, post-exit/death persistence, and normal driver
migration as both host and guest require actual game verification. Disabled
grey prompts may remain; removal of UI hints for unmodded peers is not provided.
Host migration or authority changes without a new driver were not tested.

Minimum sequence: ON caller requests A and BOTH gun-resupply zones are blocked
before anyone enters; an unmodded teammate's call and a map car stay untouched.
Repeat as host and guest, with two simultaneous calls and death during flight.
Then an ON driver protects A; leave A empty; an unmodded teammate
drives A and BOTH sides become usable; repeat with an installed-but-OFF driver;
then an ON driver takes over and both sides become blocked again. Repeat as
guest/host and with two cars, passenger/gunner entry, death, OFF on foot,
OFF while driving, and repeated swaps. Check another client's ability to use
gun resupply, not solely the old controller's local grey prompt.
