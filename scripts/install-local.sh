#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
app_name="Barkeep"
source_app="$repo_dir/dist/$app_name.app"
install_dir="${INSTALL_DIR:-$HOME/Applications}"
installed_app="$install_dir/$app_name.app"

"$repo_dir/scripts/build-app.sh"
mkdir -p "$install_dir"

pkill -f "$installed_app/Contents/MacOS/$app_name" 2>/dev/null || true
if [[ -e "$installed_app" ]]; then
    case "$installed_app" in
        "$install_dir/$app_name.app") rm -r "$installed_app" ;;
        *) echo "refusing to replace unexpected path: $installed_app" >&2; exit 70 ;;
    esac
fi

ditto "$source_app" "$installed_app"
xattr -dr com.apple.quarantine "$installed_app" 2>/dev/null || true
codesign --verify --deep --strict "$installed_app"
open -n "$installed_app"

echo "Installed $installed_app"
