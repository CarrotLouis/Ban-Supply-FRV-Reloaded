# Repository instructions

This repository contains only the Ban Supply FRV Reloaded source project.

- Preserve the per-vehicle rules, default-ON ModOptionsMenu toggle, stable option
  ID, addon resource and GUID. No custom bindings are requested.
- Use `src/` for Lua, `tests/` for offline verification, `scripts/` for tooling
  and `docs/` for evidence. Builds never implicitly deploy to the game.
- Never commit `outputs/`, `build/`, secrets, local dependencies, runtime logs,
  raw game assets or memory captures. Source ZIPs must exclude those too.
- Check game/module hashes and native fingerprints before native work. Attribute
  calls using proven native identities, never the nearest car or spawn timing.
- Keep original shared runtime modules byte-identical to `vendor-lock.json`.
- Distinguish offline results from live host/guest verification in all reports.
- The owner explicitly requests ongoing source synchronization: after each
  completed logical change, run relevant checks, review the staged diff, commit
  and push to `origin`, then confirm the remote head. This is authorization to
  synchronize this repository; no additional confirmation is needed each time.
  Never force-push. Report a blocked push without losing the local changes.
- Update the single version in `src/entry.lua`, embedded guide, changelog and
  validation notes when gameplay behavior changes.

See `CONTRIBUTING.md` for commands and the optional private-capture checks.
