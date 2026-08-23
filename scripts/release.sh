#!/bin/zsh

set -euo pipefail

repo_dir="${0:A:h:h}"
requested_build_number="${BUILD_NUMBER:-}"
source "$repo_dir/version.env"
version="${VERSION:-$MARKETING_VERSION}"
build_number="${requested_build_number:-$BUILD_NUMBER}"
notes_file="${NOTES_FILE:-RELEASE_NOTES.md}"
notary_profile="${NOTARY_PROFILE:-portmanager}"
asc_key_id="${ASC_KEY_ID:-}"
asc_issuer_id="${ASC_ISSUER_ID:-}"
asc_key_path="${ASC_KEY_PATH:-}"
sparkle_key_path="${SPARKLE_PRIVATE_KEY_PATH:-}"
sign_identity="${SIGN_IDENTITY:-}"
team_id="${DEVELOPMENT_TEAM:-JXNCT3BEVQ}"
publish="${PUBLISH:-0}"
app_name="Barkeep"
dist_dir="$repo_dir/dist"
app_path="$dist_dir/$app_name.app"
dmg_name="$app_name-$version.dmg"
dmg_path="$dist_dir/$dmg_name"

cd "$repo_dir"

if [[ ! -f "$notes_file" ]]; then
    echo "$notes_file does not exist" >&2
    exit 66
fi

if [[ "$publish" == "1" ]]; then
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        echo "make publish requires a Git repository" >&2
        exit 69
    }
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "commit the current work before publishing" >&2
        exit 65
    fi
    gh auth status >/dev/null
fi

if [[ -z "$sign_identity" ]]; then
    sign_identity="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n 's/^[^"]*"\([^"]*\)".*$/\1/p' \
            | sed -n '/^Developer ID Application: /{p;q;}'
    )"
fi

if [[ -z "$sign_identity" || "$sign_identity" == "-" ]]; then
    echo "A Developer ID Application identity is required" >&2
    exit 65
fi

VERSION="$version" BUILD_NUMBER="$build_number" SIGN_IDENTITY="$sign_identity" \
DEVELOPMENT_TEAM="$team_id" ./scripts/build-app.sh

codesign --verify --deep --strict --verbose=2 "$app_path"
sign_info="$(codesign -d --verbose=2 "$app_path" 2>&1 || true)"
if [[ "$sign_info" != *"flags="*"runtime"* ]]; then
    echo "hardened runtime is missing" >&2
    exit 65
fi

"$app_path/Contents/MacOS/$app_name" & launch_pid=$!
sleep 4
if kill -0 "$launch_pid" 2>/dev/null; then
    kill "$launch_pid"
else
    echo "the signed app exited during launch" >&2
    exit 65
fi

SKIP_BUILD=1 VERSION="$version" ./scripts/build-dmg.sh
codesign --force --sign "$sign_identity" --timestamp "$dmg_path"

if [[ -n "$asc_key_id" && -n "$asc_issuer_id" && -n "$asc_key_path" ]]; then
    xcrun notarytool submit "$dmg_path" \
        --key "$asc_key_path" \
        --key-id "$asc_key_id" \
        --issuer "$asc_issuer_id" \
        --wait
else
    xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
fi
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

generate_appcast="$(
    find "$repo_dir/.xcode-build" \
        -type f -name generate_appcast -perm -u+x -print -quit 2>/dev/null
)"
if [[ -z "$generate_appcast" ]]; then
    echo "Sparkle generate_appcast was not found" >&2
    exit 66
fi

sha256="$(shasum -a 256 "$dmg_path" | cut -d' ' -f1)"
print -r -- "$sha256  $dmg_name" > "$dmg_path.sha256"

appcast_work="$(mktemp -d)"
cleanup_appcast() {
    rm -r "$appcast_work"
}
trap cleanup_appcast EXIT

ditto "$dmg_path" "$appcast_work/$dmg_name"
cp "$notes_file" "$appcast_work/$app_name-$version.md"
cp appcast.xml "$appcast_work/appcast.xml"

appcast_args=(
    --download-url-prefix "https://github.com/iannuttall/barkeep/releases/download/v$version/"
    --embed-release-notes
    --maximum-versions 0
)
if [[ -n "$sparkle_key_path" ]]; then
    appcast_args+=(--ed-key-file "$sparkle_key_path")
fi

"$generate_appcast" \
    "${appcast_args[@]}" \
    "$appcast_work"

cp "$appcast_work/appcast.xml" appcast.xml

print -r -- "VERSION='$version'" > release.env
print -r -- "BUILD_NUMBER='$build_number'" >> release.env
print -r -- "DMG_PATH='$dmg_path'" >> release.env
print -r -- "SHA256_PATH='$dmg_path.sha256'" >> release.env

if [[ "$publish" == "1" ]]; then
    # Publish the download first. The feed cannot point at a missing file.
    gh release create "v$version" \
        "$dmg_path" \
        "$dmg_path.sha256" \
        --title "Barkeep $version" \
        --notes-file "$notes_file"

    if ! git diff --quiet -- appcast.xml; then
        git add appcast.xml
        git commit -m "chore(release): Barkeep $version"
    fi
    git push origin HEAD
fi

echo "Release ready: $dmg_path"
