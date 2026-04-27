# Changes vs. Original

Source baseline: `Original_Folder_Files/claude-desktop-debian` (working tree
at audit time, 2026-04-27). Upstream Claude pin in baseline:
`1.4758.0` (per `scripts/setup/detect-host.sh`). Local installed version at
audit time: `1.3883.0-2.0.5` (stale due to F-1 below).

## Summary

Three source-tree changes addressing three accepted findings (F-4, F-6,
F-8). Five additional findings (F-1, F-2, F-3, F-5, F-7) are listed under
**Manual follow-up** — they do not require source edits.

## Per-file changes

### scripts/packaging/deb.sh

- **Findings**: F-4 (critical/security) + F-8 (cosmetic)
- **Symptoms**:
  - F-4: After `dpkg -i`, files under `/usr/bin/claude-desktop` and
    `/usr/lib/claude-desktop/` are owned by the build-host uid (e.g.
    `1001:1001`) instead of `root:root`. Local privilege-escalation
    surface.
  - F-8: Launcher `/usr/bin/claude-desktop` contains multi-tab artifacts
    (`zenity --error \t\t\t\t--text=...`) where line continuations were
    eaten by the unquoted heredoc.
- **Change intent**:
  - F-4: Before `dpkg-deb --build`, force `chown -R 0:0` across the
    staging tree. Run as root if invoked as root, otherwise wrap the chown
    + dpkg-deb pair in `fakeroot`. Hard-error with a clear message if
    neither is available.
  - F-8: Rewrite zenity / kdialog fallback calls in the launcher heredoc
    as single lines (no `\<newline>` continuation), with a comment
    explaining why.
- **Approx. lines touched**:
  - F-4: ~20 lines added immediately before `dpkg-deb --build`.
  - F-8: 6 lines rewritten + 3-line explanatory comment, inside the
    `cat > ... << EOF` heredoc that emits the launcher.
  - Plus a one-line `MODIFIED` header after the shebang.
- **Tests covering**: `tests/test-artifact-deb.sh` (modified — see below).
- **Learnings ref**: n/a (no existing entry covers `.deb` ownership).
- **Rollback**: `cp Original_Folder_Files/claude-desktop-debian/scripts/packaging/deb.sh
  Folders_Files_With_Improvements/claude-desktop-debian/scripts/packaging/deb.sh`.

### scripts/packaging/rpm.sh

- **No change.** Initial Phase-2 plan suspected a parallel F-4 fix would
  be needed, but inspection confirmed the spec template already declares
  `%defattr(-, root, root, 0755)` and `%attr(755, root, root)
  /usr/bin/claude-desktop`, so RPM ownership is fixed at install time
  regardless of build-host uid. No edit required.

### scripts/frame-fix-wrapper.js

- **Finding**: F-6 (nice-to-have)
- **Symptom**: `~/.cache/claude-desktop-debian/launcher.log` accumulates
  `[Frame Fix] Intercepting setApplicationMenu` lines on every menu
  update — log noise + slow disk creep.
- **Change intent**: Gate that single log call behind a new boolean
  `FRAME_FIX_DEBUG`, set when `CLAUDE_DESKTOP_DEBUG=1` or
  `CLAUDE_FRAME_FIX_DEBUG=1`. All other one-shot startup logs in the file
  remain unconditional. Behaviour unchanged for users who don't set the
  env var; debuggers can opt back in.
- **Approx. lines touched**: 4 (new `FRAME_FIX_DEBUG` const + 2-line gate
  around the existing `console.log`) + 1-line `MODIFIED` header.
- **Tests covering**: none directly; `node --check
  scripts/frame-fix-wrapper.js` covered in Phase 4 verification. Manual
  smoke: launch app, confirm launcher.log no longer accumulates
  `Intercepting setApplicationMenu` lines unless
  `CLAUDE_FRAME_FIX_DEBUG=1` is set.
- **Learnings ref**: n/a.
- **Rollback**: copy original file back over.

### tests/test-artifact-deb.sh

- **Findings**: F-4 + F-8 (test coverage for both)
- **Symptom (test gap)**: Existing artifact tests assert file existence
  and basic launcher content but never verify ownership of packaged files
  or absence of heredoc artifacts.
- **Change intent**: Two new assertions inserted between the existing
  package-metadata block and the `dpkg -i` install block:
  1. `dpkg-deb -c "$deb_file"` parsed with awk + grep — fails if any
     entry's owner/group is not `root/root` (catches F-4 regressions).
  2. `dpkg-deb -x "$deb_file" $tmp` then
     `grep -qP '\t{2,}--text=' usr/bin/claude-desktop` — fails if
     heredoc-continuation artifacts return (catches F-8 regressions).
- **Approx. lines touched**: ~22 added + 1-line `MODIFIED` header.
- **Tests covering**: this file *is* the test.
- **Learnings ref**: n/a.
- **Rollback**: copy original file back over.

## Manual follow-up steps (outside this repo)

These are not changes to the source tree; they are user-side actions.
None require sudo on files this repo controls.

- **F-1 (critical) — Stale APT URL.** The user's
  `/etc/apt/sources.list.d/claude-desktop.list` contains both the
  current `pkg.claude-desktop-debian.dev` line and a legacy
  `aaddrick.github.io` line. The legacy line breaks `apt update` (https→
  http downgrade refusal) and is the root cause of the user being 875
  upstream Claude versions / 2 repo bumps behind. Fix:
  ```bash
  sudo sed -i.pre-fix '\|aaddrick\.github\.io|d' \
      /etc/apt/sources.list.d/claude-desktop.list
  sudo apt update && sudo apt upgrade claude-desktop
  ```
  Reference: upstream issues
  [#516](https://github.com/aaddrick/claude-desktop-debian/issues/516),
  [#507](https://github.com/aaddrick/claude-desktop-debian/issues/507),
  [#394](https://github.com/aaddrick/claude-desktop-debian/issues/394),
  [#352](https://github.com/aaddrick/claude-desktop-debian/issues/352),
  and `docs/learnings/apt-worker-architecture.md`.
- **F-2 — `.bak` leftover.** After F-1 succeeds, remove
  `/etc/apt/sources.list.d/claude-desktop.list.bak`.
- **F-3 — Version drift.** Resolves automatically once F-1 is fixed and
  `apt upgrade` runs. No manual step beyond F-1.
- **F-5 — `oauth:tokenCache` latent.** Only act if the user starts
  seeing 401s; remove the key from `~/.config/Claude/config.json` per
  `TROUBLESHOOTING.md`.
- **F-7 — Rotated logs.** Optional one-time cleanup:
  ```bash
  find ~/.config/Claude/logs -name 'main*.log' \
      -size +5M -mtime +30 -print
  # If output looks right, replace -print with -delete.
  ```

## Upstream-PR candidates

All three source-tree changes are good upstream contributions. Per the
plan's ground rule, **strip the `MODIFIED 2026-04-27:` header lines from
each file before opening the upstream PR** — those headers exist to make
local audits trivial; they would be noise in
`aaddrick/claude-desktop-debian`.

| Finding | File | Rationale |
|---|---|---|
| F-4 | `scripts/packaging/deb.sh` | Affects every contributor who builds locally without invoking through fakeroot. Makes ownership leakage impossible by construction. |
| F-6 | `scripts/frame-fix-wrapper.js` | Trivial, low-risk, removes a chronic source of log spam. |
| F-8 | `scripts/packaging/deb.sh` | Cosmetic but real. Clean diff. |
| (test) | `tests/test-artifact-deb.sh` | Should accompany the F-4 + F-8 PR so regressions can't sneak back. |
