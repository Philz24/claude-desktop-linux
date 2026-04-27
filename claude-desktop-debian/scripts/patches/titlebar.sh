#===============================================================================
# Title bar detection patch: strip the negation so Linux renders the frame.
#
# Sourced by: build.sh
# Sourced globals: (none)
# Modifies globals: (none)
#===============================================================================

patch_titlebar_detection() {
	echo '##############################################################'
	echo "Removing '!' from 'if (\"!\"isWindows && isMainWindow) return null;'"
	echo 'detection flag to enable title bar'

	local search_base='app.asar.contents/.vite/renderer/main_window/assets'
	local target_pattern='MainWindowPage-*.js'

	echo "Searching for '$target_pattern' within '$search_base'..."
	local target_files
	mapfile -t target_files < <(find "$search_base" -type f -name "$target_pattern")
	local num_files=${#target_files[@]}

	case $num_files in
		0)
			echo "Error: No file matching '$target_pattern' found within '$search_base'." >&2
			exit 1
			;;
		1)
			local target_file="${target_files[0]}"
			echo "Found target file: $target_file"
			sed -i -E 's/if\(!([a-zA-Z]+)[[:space:]]*&&[[:space:]]*([a-zA-Z]+)\)/if(\1 \&\& \2)/g' "$target_file"

			if grep -q -E 'if\(![a-zA-Z]+[[:space:]]*&&[[:space:]]*[a-zA-Z]+\)' "$target_file"; then
				echo "Error: Failed to replace patterns in $target_file." >&2
				exit 1
			fi
			echo "Successfully replaced patterns in $target_file"
			;;
		*)
			echo "Error: Expected exactly one file matching '$target_pattern' within '$search_base', but found $num_files." >&2
			exit 1
			;;
	esac
	echo '##############################################################'
}
