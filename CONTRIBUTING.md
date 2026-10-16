# Development

Use Windows x64 with Python 3.12. Install `requirements-dev.txt`; tests run on
real LuaJIT 2.1 through Lupa. The Win32 tests use only their own process buffers.
Set `HD2_LUPA_DIR` only when intentionally reusing an existing Lupa installation.

```powershell
python -m pip install -r requirements-dev.txt
python scripts/build.py --validate-only
```

For installable packaging, obtain BingusSharedLoader separately and pass its
checkout with `--loader`, or set `BINGUS_SHARED_LOADER`. No loader build tools
or original game data are redistributed in this repository.

```powershell
python scripts/build.py --loader C:\path\to\BingusSharedLoader --source-bundle
```

The default artifacts are under ignored `outputs/`; temporary assembly and test
reports are under ignored `build/`. Source archives use a source-directory
allowlist and cannot include their own outputs or game captures.

## Additional local evidence

Native instruction verification requires an independently retained capture for
the exact guarded game build; it is intentionally absent from Git. Supply it
explicitly. The optional raw FRV definition adds the original timer-data check.

```powershell
python scripts/build.py --validate-only --native-capture C:\path\to\capture --frv-definition C:\path\to\frv-component.bin
python tests/verify_upstream_menu.py C:\path\to\ModOptionsMenu
node scripts/verify_arsenal.cjs outputs/Ban-Supply-FRV-Reloaded-0.2.0-test.zip C:\path\to\Arsenal-source
```

The manager test uses an isolated profile and fixture game directory. Never
present emulation or this backend fixture as a live multiplayer result.
The expected live cases are listed in `docs/VALIDATION.md`.

## Source synchronization

The owner requested that completed changes be synchronized to the public
GitHub repository. After each coherent change:

1. Run the relevant validation, then `git diff --check`.
2. Review the staged paths and diff. Keep `outputs/`, `build/`, secrets, logs,
   raw assets, captures and local dependencies untracked.
3. Commit the completed source/documentation changes and push the current branch
   to `origin`. Do not force-push or rewrite published history.
4. Verify that the remote head matches the local commit. If authentication or
   networking fails, retain the local commit and report the pending push.

Change the version in `src/entry.lua` when gameplay behavior changes, and update
the embedded guide, changelog and validation status. Keep the resource name,
GUID, default-ON toggle and option ID stable across upgrades. Vendored shared
runtime files must remain byte-identical to their locked upstream revisions.
