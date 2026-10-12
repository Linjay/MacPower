#!/bin/zsh
# Install/update a published MacPower build using only tools shipped with macOS.

macpower_fail() { print -u2 -- "MacPower: $*"; exit 1; }

macpower_download() {
    /usr/bin/curl --fail --location --silent --show-error \
        --proto '=https' --proto-redir '=https' --connect-timeout 15 \
        --max-time 180 --retry 2 --output "$2" "$1"
}

macpower_version() {
    local value="${1#v}"
    [[ "$value" =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]] || return 1
    print -r -- "$value"
}

macpower_newer() {
    local -a candidate=("${(@s:.:)1}") installed=("${(@s:.:)2}")
    local i
    for i in 1 2 3; do
        (( candidate[i] > installed[i] )) && return 0
        (( candidate[i] < installed[i] )) && return 1
    done
    return 1
}

macpower_pids() {
    /bin/ps -axo pid=,comm= | /usr/bin/awk -v exe="$1/Contents/MacOS/MacPower" '
        { pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == exe) print pid }'
}

macpower_quit() {
    [[ -n "$(macpower_pids "$1")" ]] || return 0
    /usr/bin/osascript - "$1" <<'APPLESCRIPT'
on run argv
    tell application (item 1 of argv) to quit
end run
APPLESCRIPT
    local i
    for i in {1..50}; do
        [[ -z "$(macpower_pids "$1")" ]] && return 0
        /bin/sleep 0.1
    done
    print -u2 -- "旧版未能退出，安装已停止。请退出 MacPower 后重试。"
    return 1
}

macpower_open() {
    /usr/bin/open "$1" || return 1
    local i
    for i in {1..20}; do
        [[ -n "$(macpower_pids "$1")" ]] && return 0
        /bin/sleep 0.25
    done
    print -u2 -- "应用未能启动；预览版尚未公证，请查看 macOS 的启动提示。"
    return 1
}

macpower_install() {
    emulate -L zsh
    setopt errexit nounset pipefail localtraps
    local requested="" install_dir="" no_open=0 check_only=0
    while (( $# )); do
        case "$1" in
            --version|--dir)
                (( $# >= 2 )) || macpower_fail "$1 缺少参数。"
                if [[ "$1" == --version ]]; then requested="$2"; else install_dir="$2"; fi
                shift 2 ;;
            --no-open) no_open=1; shift ;;
            --check) check_only=1; shift ;;
            --help|-h)
                print -- '用法: zsh scripts/install.sh [--check] [--version 0.1.7] [--dir /Applications] [--no-open]'
                print -- '默认安装最新发布（含预览版）；再次运行即可更新，已有或更新的版本不会被覆盖。'
                return 0 ;;
            *) macpower_fail "未知参数: $1" ;;
        esac
    done
    [[ "$(/usr/bin/uname -s)" == Darwin ]] || macpower_fail '仅支持 macOS。'
    local os_version="$(/usr/bin/sw_vers -productVersion)"
    (( ${os_version%%.*} >= 14 )) || macpower_fail '需要 macOS 14 或更新版本。'
    [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == 1 ]] || macpower_fail '当前发布仅支持 Apple Silicon Mac。'

    if [[ -z "$install_dir" ]]; then
        if [[ -d /Applications/MacPower.app ]]; then install_dir=/Applications
        elif [[ -d "$HOME/Applications/MacPower.app" ]]; then install_dir="$HOME/Applications"
        elif [[ -w /Applications ]]; then install_dir=/Applications
        else install_dir="$HOME/Applications"
        fi
    fi
    install_dir="${install_dir:A}"
    local target="$install_dir/MacPower.app"
    [[ ! -L "$target" ]] || macpower_fail "安装位置是符号链接，请指定实际应用目录: $target"
    local installed=""
    if [[ -e "$target" ]]; then
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist" 2>/dev/null)" == app.macpower.local ]] || macpower_fail "安装位置已有其他文件: $target"
        installed="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
        installed="$(macpower_version "$installed")" || macpower_fail '已有应用的版本号无效。'
    fi

    local workspace="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/macpower.XXXXXX")"
    local stage="" new_installed=0 complete=0 was_running=0 lock=""
    # zsh runs a function's EXIT trap after restoring that function's locals.
    # Keep transaction state in this outer scope so cleanup can still access it.
    () {
        # Until launch succeeds, any error or interruption restores the previous app.
        trap '
            local result=$?
            if (( ! complete )); then
                # Inspect the renamed bundle, including interruption between a move
                # and its following command; never discard an un-restored backup.
                if [[ -n "$stage" && -d "$stage/previous.app" ]]; then
                    if /bin/rm -rf -- "$target" && /bin/mv -- "$stage/previous.app" "$target"; then
                        print -u2 -- "已恢复旧版 MacPower。"
                    else
                        print -u2 -- "旧版保留在 $stage/previous.app，请手动恢复。"
                        stage=""
                    fi
                elif (( new_installed )); then
                    /bin/rm -rf -- "$target"
                fi
                if (( was_running )) && [[ -d "$target" ]]; then macpower_open "$target" || true; fi
            fi
            [[ -n "$stage" ]] && /bin/rm -rf -- "$stage"
            [[ -n "$lock" ]] && /bin/rmdir -- "$lock" 2>/dev/null
            /bin/rm -rf -- "$workspace"
            return $result
        ' EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM HUP

        local version
        if [[ -n "$requested" ]]; then
            version="$(macpower_version "$requested")" || macpower_fail '版本号应为 0.1.7 或 v0.1.7 这样的格式。'
        else
            print -- '正在检查最新发布（含预览版）…'
            macpower_download 'https://github.com/Linjay/MacPower/releases.atom' "$workspace/releases.atom" || macpower_fail '无法读取发布订阅，旧版未更改。'
            local link="$(/usr/bin/xmllint --nonet --xpath 'string((/*[local-name()="feed"]/*[local-name()="entry"])[1]/*[local-name()="link"][@rel="alternate"]/@href)' "$workspace/releases.atom")"
            [[ "$link" == https://github.com/Linjay/MacPower/releases/tag/v* ]] || macpower_fail '发布订阅没有有效的 MacPower 版本。'
            version="$(macpower_version "${link##*/}")" || macpower_fail '最新发布的版本号无法识别。'
        fi
        print -- "已安装: ${installed:-无}；目标版本: $version；安装位置: $target"
        if (( check_only )); then complete=1; return 0; fi
        if [[ -n "$installed" ]] && ! macpower_newer "$version" "$installed"; then
            print -- '已安装相同或更新的版本，无需替换。'
            complete=1
            return 0
        fi
        /bin/mkdir -p -- "$install_dir"
        [[ -w "$install_dir" && ( ! -e "$target" || -w "$target" ) ]] || macpower_fail "没有安装目录的写入权限。可用 --dir \"\$HOME/Applications\" 安装到个人目录。"
        # Atomic mkdir prevents two installers from replacing the same app concurrently.
        /bin/mkdir -- "$install_dir/.MacPower-install.lock" 2>/dev/null || macpower_fail "另一个安装任务正在运行；若上次安装被强制终止，请检查 $install_dir/.MacPower-install.lock。"
        lock="$install_dir/.MacPower-install.lock"
        local archive="MacPower-$version-arm64.zip"
        local base="https://github.com/Linjay/MacPower/releases/download/v$version"
        print -- "正在下载并校验 MacPower $version…"
        macpower_download "$base/SHA256SUMS" "$workspace/SHA256SUMS" || macpower_fail '无法下载校验文件，旧版未更改。'
        macpower_download "$base/$archive" "$workspace/$archive" || macpower_fail '无法下载当前架构的安装包，旧版未更改。'
        local expected="$(/usr/bin/awk -v asset="$archive" '$2 == asset || $2 == "*" asset {print $1}' "$workspace/SHA256SUMS")"
        [[ "$expected" =~ '^[0-9a-fA-F]{64}$' ]] || macpower_fail '发布校验文件缺少唯一、有效的 SHA-256。'
        local actual="$(/usr/bin/shasum -a 256 "$workspace/$archive")"
        [[ "${actual%% *}" == "${expected:l}" ]] || macpower_fail 'SHA-256 校验失败，旧版未更改。'
        /usr/bin/unzip -tq "$workspace/$archive" >/dev/null
        /usr/bin/unzip -Z1 "$workspace/$archive" > "$workspace/entries"
        local entry
        while IFS= read -r entry; do
            [[ "$entry" == MacPower.app/* && "$entry" != *'/../'* && "$entry" != *'/..' ]] || macpower_fail '安装包包含意外路径。'
        done < "$workspace/entries"
        # Bundles produced by package-release.sh have no symlinks.
        /usr/bin/unzip -Z -l "$workspace/$archive" > "$workspace/permissions"
        if /usr/bin/awk '$1 ~ /^l/ {found=1} END {exit !found}' "$workspace/permissions"; then macpower_fail '安装包包含意外符号链接。'; fi
        /usr/bin/ditto -x -k "$workspace/$archive" "$workspace/unpacked"
        local app="$workspace/unpacked/MacPower.app" plist="$workspace/unpacked/MacPower.app/Contents/Info.plist"
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")" == app.macpower.local ]] || macpower_fail '安装包标识不匹配。'
        [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" == "$version" ]] || macpower_fail '安装包版本不匹配。'
        [[ -x "$app/Contents/MacOS/MacPower" ]] || macpower_fail '安装包缺少可执行文件。'
        # lipo is an Xcode/Command Line Tools shim on macOS; file is a system tool.
        local executable_format="$(/usr/bin/file -b "$app/Contents/MacOS/MacPower")"
        [[ "$executable_format" =~ 'Mach-O 64-bit executable arm64([^[:alnum:]_]|$)' ]] || macpower_fail '安装包不包含 arm64 可执行文件。'
        /usr/bin/codesign --verify --deep --strict "$app"

        stage="$(/usr/bin/mktemp -d "$install_dir/.MacPower-install.XXXXXX")"
        /usr/bin/ditto --noextattr "$app" "$stage/MacPower.app"
        /usr/bin/codesign --verify --deep --strict "$stage/MacPower.app"
        [[ -n "$(macpower_pids "$target")" ]] && was_running=1
        macpower_quit "$target" || macpower_fail '旧版退出失败。'
        if [[ -d "$target" ]]; then
            /bin/mv -- "$target" "$stage/previous.app"
        fi
        new_installed=1
        /bin/mv -- "$stage/MacPower.app" "$target"
        /usr/bin/codesign --verify --deep --strict "$target"
        if (( ! no_open )); then macpower_open "$target" || macpower_fail '新版启动失败。'; fi
        complete=1
        print -- "MacPower $version 已安装: $target"
        print -- '历史和设置已保留。以后再次运行同一命令即可更新。'
    }
}

# Sourcing permits offline integration checks to substitute network and lifecycle operations.
if [[ "$ZSH_EVAL_CONTEXT" == toplevel ]]; then macpower_install "$@"; fi
