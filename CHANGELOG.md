# Changelog

## 0.2.0 — 2026-10-17

- Added automatic activation for the enabled caller's Supply FRV when its native
  transport cargo and interactions become ready; driving first is unnecessary.
- Retained driving activation, per-car persistence and native restoration for
  unmodded or feature-OFF new drivers.
- Linked the actual cargo entity to the native caller avatar, retaining local
  avatar attribution across respawn and resolving guests by session-peer slot.
- Consumed each delivery once, preventing the original caller's lingering
  transport metadata from overriding a later driver's restoration.
- Standardized the source project, ignored local outputs and documented the
  owner's validation/commit/push synchronization workflow.
- Offline checks passed; live 0.2.0 multiplayer acceptance remains pending.

## 0.1.1 — 2026-10-14

- Replaced the unreliable pre-handoff restoration window with vanilla
  delayed-enable recovery, allowing an unmodded new owner to restore both zones.
- Preserved stable vehicle identity when network IDs change during migration.
- Verified captured native behavior offline; live acceptance remained pending.

## 0.1.0 — 2026-10-12

- Initial driver-triggered prototype with one default-ON ModOptionsMenu toggle.
- Known defect: a transfer missed between Lua polls could leave gun resupply
  disabled for an unmodded new driver. Superseded by 0.1.1.
