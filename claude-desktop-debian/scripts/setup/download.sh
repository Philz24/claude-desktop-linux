#===============================================================================
# Claude installer download and extraction into work_dir/claude-extract.
#
# Sourced by: build.sh
# Sourced globals:
#   work_dir, claude_exe_filename, local_exe_path, architecture,
#   claude_download_url, claude_exe_sha256, project_root, release_tag
# Modifies globals:
#   claude_extract_dir, version
#===============================================================================

download_claude_installer() {
	section_header 'Download the latest Claude executable'

	local claude_exe_path="$work_dir/$claude_exe_filename"

	if [[ -n $local_exe_path ]]; then
		echo "Using local Claude installer: $local_exe_path"
		if [[ ! -f $local_exe_path ]]; then
			echo "Local installer file not found: $local_exe_path" >&2
			exit 1
		fi
		cp "$local_exe_path" "$claude_exe_path" || exit 1
		echo 'Local installer copied to build directory'
	else
		echo "Downloading Claude Desktop installer for $architecture..."
		if ! wget -O "$claude_exe_path" "$claude_download_url"; then
			echo "Failed to download Claude Desktop installer from $claude_download_url" >&2
			exit 1
		fi
		echo "Download complete: $claude_exe_filename"

		if ! verify_sha256 "$claude_exe_path" \
			"$claude_exe_sha256" 'Claude Desktop installer'; then
			exit 1
		fi
	fi

	echo "Extracting resources from $claude_exe_filename into separate directory..."
	claude_extract_dir="$work_dir/claude-extract"
	mkdir -p "$claude_extract_dir" || exit 1

	if ! 7z x -y "$claude_exe_path" -o"$claude_extract_dir"; then
		echo 'Failed to extract installer' >&2
		cd "$project_root" || exit 1
		exit 1
	fi

	cd "$claude_extract_dir" || exit 1
	local nupkg_path_relative
	nupkg_path_relative=$(find . -maxdepth 1 -name 'AnthropicClaude-*.nupkg' | head -1)

	if [[ -z $nupkg_path_relative ]]; then
		echo "Could not find AnthropicClaude nupkg file in $claude_extract_dir" >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo "Found nupkg: $nupkg_path_relative (in $claude_extract_dir)"

	version=$(echo "$nupkg_path_relative" | LC_ALL=C grep -oP 'AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+(?=-full|-arm64-full)')
	if [[ -z $version ]]; then
		echo "Could not extract version from nupkg filename: $nupkg_path_relative" >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo "Detected Claude version: $version"

	# Extract wrapper version from release tag if provided (e.g., v1.3.2+claude1.1.799 -> 1.3.2)
	if [[ -n $release_tag ]]; then
		local wrapper_version
		# Extract version between 'v' and '+claude' (e.g., v1.3.2+claude1.1.799 -> 1.3.2)
		wrapper_version=$(echo "$release_tag" | LC_ALL=C grep -oP '^v\K[0-9]+\.[0-9]+\.[0-9]+(?=\+claude)')
		if [[ -n $wrapper_version ]]; then
			version="${version}-${wrapper_version}"
			echo "Package version with wrapper suffix: $version"
		else
			echo "Warning: Could not extract wrapper version from release tag: $release_tag" >&2
		fi
	fi

	if ! 7z x -y "$nupkg_path_relative"; then
		echo 'Failed to extract nupkg' >&2
		cd "$project_root" || exit 1
		exit 1
	fi
	echo 'Resources extracted from nupkg'

	cd "$project_root" || exit 1
}
