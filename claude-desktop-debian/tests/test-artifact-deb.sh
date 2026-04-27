#!/usr/bin/env bash
# MODIFIED 2026-04-27: assert root:root ownership and no multi-tab artifacts in launcher (F-4, F-8)
# Integration tests for .deb package artifacts

artifact_dir="${1:?Usage: $0 <artifact-dir>}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/test-artifact-common.sh
source "$script_dir/test-artifact-common.sh"

# Find the .deb file
deb_file=$(find "$artifact_dir" -name '*.deb' -type f | head -1)
if [[ -z $deb_file ]]; then
	fail "No .deb file found in $artifact_dir"
	print_summary
fi
pass "Found deb: $(basename "$deb_file")"

# --- Package metadata ---
pkg_info=$(dpkg-deb -I "$deb_file")

if [[ $pkg_info == *'Package: claude-desktop'* ]]; then
	pass "Package name is claude-desktop"
else
	fail "Package name is not claude-desktop"
fi

if [[ $pkg_info == *'Architecture: amd64'* ]]; then
	pass "Architecture is amd64"
else
	fail "Architecture is not amd64"
fi

if [[ $pkg_info == *'Version:'* ]]; then
	pass "Version field present"
else
	fail "Version field missing"
fi

# --- F-4: assert all packaged files owned by root:root ---
# dpkg-deb -c lists entries as "perms owner/group size date path".
# Anything other than 'root/root' indicates leaked build-host uids.
non_root=$(dpkg-deb -c "$deb_file" \
	| awk '{print $2}' | grep -v '^root/root$' | sort -u || true)
if [[ -z $non_root ]]; then
	pass "All packaged files owned by root:root"
else
	fail "Non-root ownership in package: $non_root"
fi

# --- F-8: assert launcher has no multi-tab artifacts from heredoc ---
# Extract the .deb to a temp dir and grep the launcher.
tmp_extract=$(mktemp -d)
trap 'rm -rf "$tmp_extract"' EXIT
if dpkg-deb -x "$deb_file" "$tmp_extract"; then
	launcher="$tmp_extract/usr/bin/claude-desktop"
	if [[ -f $launcher ]] \
		&& ! grep -qP '\t{2,}--text=' "$launcher"; then
		pass "Launcher has no multi-tab heredoc artifacts"
	else
		fail "Launcher contains multi-tab artifacts (heredoc continuation lost)"
	fi
fi

# --- Install the package ---
# Use --force-depends since we only care about file placement
if sudo dpkg -i --force-depends "$deb_file"; then
	pass "dpkg -i succeeded"
else
	fail "dpkg -i failed"
fi

# --- File existence checks ---
assert_executable '/usr/bin/claude-desktop'
assert_file_exists '/usr/share/applications/claude-desktop.desktop'
assert_dir_exists '/usr/lib/claude-desktop'
assert_file_exists '/usr/lib/claude-desktop/launcher-common.sh'

# Electron binary
electron_path='/usr/lib/claude-desktop/node_modules/electron/dist/electron'
assert_file_exists "$electron_path"
assert_executable "$electron_path"

# chrome-sandbox
assert_file_exists \
	'/usr/lib/claude-desktop/node_modules/electron/dist/chrome-sandbox'

# --- Desktop entry validation ---
desktop_file='/usr/share/applications/claude-desktop.desktop'
assert_contains "$desktop_file" 'Exec=/usr/bin/claude-desktop' \
	"Desktop entry Exec field correct"
assert_contains "$desktop_file" 'Type=Application' \
	"Desktop entry Type field correct"
assert_contains "$desktop_file" 'Icon=claude-desktop' \
	"Desktop entry Icon field correct"

# Validate desktop file syntax if tool available
if command -v desktop-file-validate &>/dev/null; then
	assert_command_succeeds "desktop-file-validate passes" \
		desktop-file-validate "$desktop_file"
fi

# --- Icons ---
icon_dir='/usr/share/icons/hicolor'
icon_found=false
for size in 16 24 32 48 64 256; do
	if [[ -f "$icon_dir/${size}x${size}/apps/claude-desktop.png" ]]; then
		icon_found=true
	fi
done
if [[ $icon_found == true ]]; then
	pass "At least one icon installed in hicolor"
else
	fail "No icons found in hicolor"
fi

# --- Launcher script content ---
assert_contains '/usr/bin/claude-desktop' 'launcher-common.sh' \
	"Launcher sources launcher-common.sh"
assert_contains '/usr/bin/claude-desktop' 'run_doctor' \
	"Launcher references run_doctor"
assert_contains '/usr/bin/claude-desktop' 'build_electron_args' \
	"Launcher calls build_electron_args"

# --- App contents (asar) ---
resources_dir='/usr/lib/claude-desktop/node_modules/electron/dist/resources'
validate_app_contents "$resources_dir"

# --- Doctor smoke test ---
# --doctor checks system state; some checks will fail in CI (no display,
# etc.) but the script itself should not crash with signal or 127.
doctor_exit=0
/usr/bin/claude-desktop --doctor >/dev/null 2>&1 || doctor_exit=$?
if [[ $doctor_exit -lt 127 ]]; then
	pass "--doctor runs without crashing (exit: $doctor_exit)"
else
	fail "--doctor crashed (exit: $doctor_exit)"
fi

print_summary
