#!/usr/bin/env bash

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
pushd "$script_dir" >/dev/null || exit 1
echo "Building Playbook..."
ATLAS_BUILD_SCRIPT="$script_dir/dependencies/local-build.ps1" pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command '& $env:ATLAS_BUILD_SCRIPT -AddLiveLog -ReplaceOldPlaybook -Removals @("WinverRequirement", "Verification") -DontOpenPbLocation'
build_exit=$?
if [ "$build_exit" -ne 0 ]; then
    if [ "$#" -eq 0 ]; then
        read -p "Press Enter to exit...: "
    fi
fi
popd >/dev/null || exit 1
exit "$build_exit"
