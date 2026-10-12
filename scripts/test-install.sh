#!/bin/zsh
# Offline integration checks use a real signed bundle but never open an app.
set -euo pipefail
cd "${0:A:h:h}"
ROOT="$PWD"
FIXTURE_APP="${1:-$ROOT/build/command-install/MacPower.app}"
[[ -d "$FIXTURE_APP" ]] || { print -u2 '先运行 scripts/build-app.sh，再传入生成的 MacPower.app 路径。'; exit 1; }
WORK=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macpower-install-tests.XXXXXX")
trap '/bin/rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/assets" "$WORK/source" "$WORK/base"
# Pin only the disposable fixture metadata, so future app versions can run this suite.
/usr/bin/ditto "$FIXTURE_APP" "$WORK/base/MacPower.app"
FIXTURE_APP="$WORK/base/MacPower.app"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.7' "$FIXTURE_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$FIXTURE_APP" 2>/dev/null
/usr/bin/ditto "$FIXTURE_APP" "$WORK/source/MacPower.app"

make_asset() {
    local folder="$1"
    mkdir -p "$folder"
    /usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$WORK/source/MacPower.app" "$folder/MacPower-0.1.7-arm64.zip"
    (cd "$folder"; /usr/bin/shasum -a 256 MacPower-0.1.7-arm64.zip > SHA256SUMS)
}
make_asset "$WORK/assets"
# Correct checksum, wrong embedded version.
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.6' "$WORK/source/MacPower.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$WORK/source/MacPower.app" 2>/dev/null
make_asset "$WORK/wrong-version"
/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.1.7' "$WORK/source/MacPower.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$WORK/source/MacPower.app" 2>/dev/null
# Correct version/checksum, corrupted signature.
print -- 'corrupted' >> "$WORK/source/MacPower.app/Contents/MacOS/MacPower"
make_asset "$WORK/bad-signature"

cat > "$WORK/releases.atom" <<'ATOM'
<feed xmlns="http://www.w3.org/2005/Atom"><entry><link rel="alternate" href="https://github.com/Linjay/MacPower/releases/tag/v0.1.7"/></entry></feed>
ATOM
cat > "$WORK/invalid.atom" <<'ATOM'
<feed xmlns="http://www.w3.org/2005/Atom"><entry><link rel="alternate" href="https://example.com/v0.1.7"/></entry></feed>
ATOM

run_case() {
    local label="$1" scenario="$2" prior="$3" expect="$4"
    local dir="$WORK/$label/Applications with spaces"
    mkdir -p "$dir"
    local before=""
    if [[ -n "$prior" ]]; then
        /usr/bin/ditto "$FIXTURE_APP" "$dir/MacPower.app"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $prior" "$dir/MacPower.app/Contents/Info.plist"
        /usr/bin/codesign --force --sign - "$dir/MacPower.app" 2>/dev/null
        before=$(/usr/bin/shasum -a 256 "$dir/MacPower.app/Contents/Info.plist")
    fi
    [[ "$scenario" == locked ]] && mkdir "$dir/.MacPower-install.lock"
    local result
    if /bin/zsh -c '
        source "$1"
        fixture_root="$2" scenario="$3" fixture_target="$4"
        if [[ "$scenario" == no-developer-tools ]]; then
            export DEVELOPER_DIR="$fixture_root/missing-developer-tools"
        fi
        macpower_download() {
            print -r -- "$1" >> "$fixture_target/downloads.log"
            if [[ "$scenario" == download-failure && "$1" == *.zip ]]; then return 22; fi
            if [[ "$1" == *.atom ]]; then
                local feed="$fixture_root/releases.atom"
                [[ "$scenario" == invalid-feed ]] && feed="$fixture_root/invalid.atom"
                /bin/cp "$feed" "$2"
            else
                local assets="$fixture_root/assets"
                [[ "$scenario" == wrong-version ]] && assets="$fixture_root/wrong-version"
                [[ "$scenario" == bad-signature ]] && assets="$fixture_root/bad-signature"
                /bin/cp "$assets/${1##*/}" "$2"
                if [[ "$scenario" == bad-checksum && "$1" == */SHA256SUMS ]]; then
                    print -- "0000000000000000000000000000000000000000000000000000000000000000  MacPower-0.1.7-arm64.zip" > "$2"
                fi
            fi
        }
        macpower_pids() { return 0; }
        macpower_quit() { [[ "$scenario" != quit-failure ]]; }
        macpower_open() {
            if [[ "$scenario" == interrupted ]]; then kill -TERM $$; fi
            [[ "$scenario" != launch-failure ]]
        }
        if [[ "$scenario" == launch-failure || "$scenario" == interrupted ]]; then macpower_install --dir "$fixture_target"
        elif [[ "$scenario" == check ]]; then macpower_install --dir "$fixture_target" --check
        else macpower_install --dir "$fixture_target" --no-open
        fi
    ' macpower-test "$ROOT/scripts/install.sh" "$WORK" "$scenario" "$dir" > "$WORK/$label.log" 2>&1; then result=0; else result=$?; fi
    if [[ "$expect" == failed && "$result" == 0 || "$expect" != failed && "$result" != 0 ]]; then
        print -u2 -- "FAIL $label: unexpected exit status $result"
        cat "$WORK/$label.log"
        return 1
    fi
    if [[ "$expect" == installed ]]; then
        [[ "$result" == 0 ]]
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dir/MacPower.app/Contents/Info.plist")" == 0.1.7 ]]
        /usr/bin/codesign --verify --deep --strict "$dir/MacPower.app" 2>/dev/null
    else
        if [[ "$expect" == failed ]]; then (( result != 0 )); else [[ "$result" == 0 ]]; fi
        if [[ -n "$prior" ]]; then
            [[ "$(/usr/bin/shasum -a 256 "$dir/MacPower.app/Contents/Info.plist")" == "$before" ]]
            /usr/bin/codesign --verify --deep --strict "$dir/MacPower.app" 2>/dev/null
        else [[ ! -e "$dir/MacPower.app" ]]; fi
    fi
    if [[ "$scenario" == locked ]]; then [[ -d "$dir/.MacPower-install.lock" ]]
    else [[ ! -e "$dir/.MacPower-install.lock" ]]; fi
    [[ -z "$(/usr/bin/find "$dir" -maxdepth 1 -name '.MacPower-install.*' ! -name '*.lock' -print)" ]]
    if [[ "$scenario" == equal || "$scenario" == newer || "$scenario" == check ]]; then
        [[ "$(/usr/bin/wc -l < "$dir/downloads.log" | tr -d ' ')" == 1 ]]
    fi
    print -- "PASS $label"
}

run_case fresh fresh '' installed
run_case no-developer-tools no-developer-tools '' installed
run_case upgrade upgrade 0.1.6 installed
run_case equal equal 0.1.7 unchanged
run_case newer newer 0.1.8 unchanged
run_case check check 0.1.6 unchanged
run_case download-failure download-failure 0.1.6 failed
run_case bad-checksum bad-checksum 0.1.6 failed
run_case wrong-version wrong-version 0.1.6 failed
run_case bad-signature bad-signature 0.1.6 failed
run_case quit-failure quit-failure 0.1.6 failed
run_case launch-rollback launch-failure 0.1.6 failed
run_case fresh-launch-failure launch-failure '' failed
run_case interrupted-update interrupted 0.1.6 failed
run_case concurrent-install locked 0.1.6 failed
run_case invalid-feed invalid-feed 0.1.6 failed
/bin/zsh -c 'source "$1"; macpower_newer 0.1.10 0.1.9; ! macpower_newer 0.1.9 0.1.10; ! macpower_version "../../0.1.7"' test "$ROOT/scripts/install.sh"
print -- 'PASS numeric-version-and-invalid-tag'
/bin/zsh -c '
    source "$1"
    attempt=0
    macpower_asset_addresses() { print "unexpected text\n185.199.108.133"; }
    macpower_curl() {
        (( attempt += 1 ))
        if (( attempt == 1 )); then return 28; fi
        [[ " $* " == *" --resolve release-assets.githubusercontent.com:443:185.199.108.133 "* ]]
    }
    macpower_download "https://github.com/Linjay/MacPower/releases/download/v0.1.7/SHA256SUMS" unused
    [[ "$attempt" == 2 ]]
' test "$ROOT/scripts/install.sh"
print -- 'PASS release-asset-dns-retry'
/bin/zsh -c '
    source "$1"
    attempt=0
    macpower_asset_addresses() { print "185.199.108.133"; }
    macpower_curl() { (( attempt += 1 )); return 28; }
    if macpower_download "https://github.com/Linjay/MacPower/releases.atom" unused; then exit 1; fi
    [[ "$attempt" == 1 ]]
    attempt=0
    macpower_curl() { (( attempt += 1 )); return 22; }
    if macpower_download "https://github.com/Linjay/MacPower/releases/download/v0.1.7/SHA256SUMS" unused; then exit 1; fi
    [[ "$attempt" == 1 ]]
' test "$ROOT/scripts/install.sh"
print -- 'PASS no-dns-retry-for-feed-or-http-errors'
print -- '19 offline installer checks passed; no app was launched or user history changed.'
