# Build & Test Plan

This document describes how to build, install, smoke-test, and roll back
the modified source tree at `Folders_Files_With_Improvements/claude-desktop-debian/`.
**Nothing in this document has been executed by the audit run** — these
are the commands you run when you're ready.

## Pre-flight (one-time)

Make sure these tools are installed:

```bash
sudo apt install -y \
    build-essential fakeroot dpkg-dev p7zip-full wget \
    nodejs npm shellcheck
```

`fakeroot` is **required** by the F-4 fix unless you're running the build
as root — otherwise `scripts/packaging/deb.sh` will hard-error with a
clear message before invoking `dpkg-deb`.

Confirm architecture: `uname -m` should be `x86_64` (amd64) or `aarch64`
(arm64). The build supports both.

Disk: budget ~10 GB free in the build directory. The Electron download
plus extraction plus packaging staging adds up.

## Build

From the modified tree:

```bash
cd "Folders_Files_With_Improvements/claude-desktop-debian"
./build.sh --build deb --clean yes
```

Adjust `--build` per your target:

- `--build deb` → produces `test-build/claude-desktop_<version>_amd64.deb`
  (or `_arm64.deb`).
- `--build appimage` → produces `test-build/claude-desktop-<version>-amd64.AppImage`.
- `--build rpm` → produces `test-build/claude-desktop-<version>.x86_64.rpm`.

Time: 15–30 min on a fast amd64 box (first build); subsequent builds with
`--clean no` are faster.

## Install (.deb path — recommended for this audit)

```bash
sudo dpkg -i test-build/claude-desktop_*_amd64.deb \
    || sudo apt --fix-broken install -y
```

Note: this **replaces** the running install. Per the project's operational
constraint (Claude Code is hosted *inside* the live Claude Desktop app),
the live session will end when the app restarts. Plan accordingly:
finish the audit / save state before installing, then install in a
separate terminal session.

### AppImage path (does not affect the .deb install)

```bash
mkdir -p ~/Applications
cp test-build/claude-desktop-*.AppImage ~/Applications/
chmod +x ~/Applications/claude-desktop-*.AppImage
~/Applications/claude-desktop-*.AppImage 2>&1 \
    | tee ~/.cache/claude-desktop-debian/launcher.log
```

This runs out-of-tree without touching `/usr/bin/claude-desktop`.

## Smoke tests (post-install)

Run these in order. Each one corresponds to an accepted finding.

### Smoke 1: doctor still works

```bash
claude-desktop --doctor
```

Expect 10 OK lines (package, display, menu-bar, electron, chrome-sandbox,
cowork socket, system tools, kernel, virtiofsd, XDG). No regression vs
the audit baseline.

### Smoke 2: F-4 — package files now owned by root

```bash
stat -c '%U:%G %a %n' \
    /usr/bin/claude-desktop \
    /usr/lib/claude-desktop \
    /usr/lib/claude-desktop/launcher-common.sh \
    /usr/lib/claude-desktop/node_modules/electron/dist/chrome-sandbox
```

Expected (was `1001:1001` for the first three before fix):

```
root:root 755 /usr/bin/claude-desktop
root:root 755 /usr/lib/claude-desktop
root:root 644 /usr/lib/claude-desktop/launcher-common.sh
root:root 4755 /usr/lib/claude-desktop/node_modules/electron/dist/chrome-sandbox
```

### Smoke 3: F-8 — launcher heredoc artifacts gone

```bash
grep -nP '\t{2,}--text=' /usr/bin/claude-desktop && echo FAIL || echo OK
```

Expect `OK`. Before the fix this would print the offending line on stdout.

### Smoke 4: F-6 — frame-fix log spam gone

Launch the app fresh, use it for a minute (open menus, switch windows),
then:

```bash
grep -c 'Intercepting setApplicationMenu' \
    ~/.cache/claude-desktop-debian/launcher.log
```

Expect a low count (close to 0 — the wrapper-loaded line still fires
once, but per-menu-update spam is gone). Before the fix, this would
typically be in the hundreds.

To re-enable the verbose log for debugging:

```bash
CLAUDE_FRAME_FIX_DEBUG=1 claude-desktop 2>&1 \
    | tee ~/.cache/claude-desktop-debian/launcher.log
```

### Smoke 5: artifact tests (run before install if possible)

```bash
cd "Folders_Files_With_Improvements/claude-desktop-debian"
./tests/test-artifact-deb.sh test-build/
```

The test installs the .deb (`sudo dpkg -i`) as part of its run, so it
asks for sudo. New assertions (F-4 ownership, F-8 launcher artifacts)
must pass.

## Manual follow-ups (per CHANGES.md)

After install + smoke tests pass:

```bash
# F-1 + F-2: clean up legacy APT URL and .bak file
sudo sed -i.pre-fix '\|aaddrick\.github\.io|d' \
    /etc/apt/sources.list.d/claude-desktop.list
sudo rm -f /etc/apt/sources.list.d/claude-desktop.list.bak
sudo apt update
```

After this, `apt update` should succeed against
`pkg.claude-desktop-debian.dev` only.

## Rollback

If the new build misbehaves, revert to the previous installed version:

```bash
# Reinstall the cached previous .deb (path varies by distro)
ls /var/cache/apt/archives/claude-desktop_*.deb
sudo dpkg -i /var/cache/apt/archives/claude-desktop_<previous>_amd64.deb
```

Or, after F-1 is applied so apt works again:

```bash
sudo apt install --reinstall claude-desktop=<previous-version>
```

To revert source-tree edits in the improvements folder:

```bash
ORIG="Original_Folder_Files/claude-desktop-debian"
DST="Folders_Files_With_Improvements/claude-desktop-debian"
cp "$ORIG/scripts/packaging/deb.sh"          "$DST/scripts/packaging/deb.sh"
cp "$ORIG/scripts/frame-fix-wrapper.js"      "$DST/scripts/frame-fix-wrapper.js"
cp "$ORIG/tests/test-artifact-deb.sh"        "$DST/tests/test-artifact-deb.sh"
```

## Upstream PR checklist (when ready)

If you decide to upstream F-4 / F-6 / F-8 to
`aaddrick/claude-desktop-debian`:

1. Strip the `MODIFIED 2026-04-27:` header lines from each modified
   file. They are local-fork audit aids, not upstream-appropriate.
2. Open one PR per finding (or one combined PR if related) referencing
   the relevant evidence. F-4 is the only one with security implications
   — call that out in the PR description.
3. Run the project's lint stack (`shellcheck`, `actionlint`, `codespell`,
   per `STYLEGUIDE.md`) before pushing.
4. Confirm the test additions in `tests/test-artifact-deb.sh` pass in
   CI on amd64 and arm64.
