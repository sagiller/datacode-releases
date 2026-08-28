#!/usr/bin/env bash
set -euo pipefail

# Adapted from the MIT-licensed installer inherited with the current upstream baseline.
# Platform and PATH handling stay close to that source; DataCode-specific release
# resolution and integrity validation are intentionally isolated below.
APP=datacode
REPOSITORY=sagiller/datacode-releases
RELEASES="https://github.com/$REPOSITORY/releases"

MUTED='\033[0;2m'
RED='\033[0;31m'
ORANGE='\033[38;5;214m'
NC='\033[0m' # No Color


usage() {
    cat <<EOF
DataCode Installer

Usage: install [options]

Options:
    -h, --help              Display this help message
    -v, --version <version> Install a specific stable version (e.g., 1.0.5)
    -b, --binary <path>     Install from a local binary instead of downloading
        --no-modify-path    Don't modify shell config files (.zshrc, .bashrc, etc.)

Examples:
    curl -fsSL https://raw.githubusercontent.com/sagiller/datacode-releases/main/install.sh | bash
    curl -fsSL https://raw.githubusercontent.com/sagiller/datacode-releases/main/install.sh | bash -s -- --version 1.0.5
    ./datacode/install.sh --binary /path/to/datacode
EOF
}


requested_version=${VERSION:-}
no_modify_path=false
binary_path=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--version)
            if [[ -n "${2:-}" ]]; then
                requested_version="$2"
                shift 2
            else
                echo -e "${RED}Error: --version requires a version argument${NC}"
                exit 1
            fi
            ;;
        -b|--binary)
            if [[ -n "${2:-}" ]]; then
                binary_path="$2"
                shift 2
            else
                echo -e "${RED}Error: --binary requires a path argument${NC}"
                exit 1
            fi
            ;;
        --no-modify-path)
            no_modify_path=true
            shift
            ;;
        *)
            echo -e "${ORANGE}Warning: Unknown option '$1'${NC}" >&2
            shift
            ;;
    esac
done

if [ -n "$binary_path" ] && [ -n "$requested_version" ]; then
    echo -e "${RED}Error: --binary and --version cannot be used together${NC}"
    exit 1
fi

INSTALL_DIR=$HOME/.datacode/bin
mkdir -p "$INSTALL_DIR"

# If --binary is provided, skip all download/detection logic
if [ -n "$binary_path" ]; then
    if [ ! -f "$binary_path" ]; then
        echo -e "${RED}Error: Binary not found at ${binary_path}${NC}"
        exit 1
    fi
    specific_version="local"
else
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}Error: 'curl' is required but not installed.${NC}"
        exit 1
    fi
    raw_os=$(uname -s)
    os=$(echo "$raw_os" | tr '[:upper:]' '[:lower:]')
    case "$raw_os" in
      Darwin*) os="darwin" ;;
      Linux*) os="linux" ;;
    esac

    arch=$(uname -m)
    if [[ "$arch" == "aarch64" ]]; then
      arch="arm64"
    fi
    if [[ "$arch" == "x86_64" ]]; then
      arch="x64"
    fi

    if [ "$os" = "darwin" ] && [ "$arch" = "x64" ]; then
      rosetta_flag=$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)
      if [ "$rosetta_flag" = "1" ]; then
        arch="arm64"
      fi
    fi

    combo="$os-$arch"
    case "$combo" in
      linux-x64|linux-arm64|darwin-x64|darwin-arm64)
        ;;
      *)
        echo -e "${RED}Unsupported OS/Arch: $os/$arch${NC}"
        exit 1
        ;;
    esac

    archive_ext=".zip"
    if [ "$os" = "linux" ]; then
      archive_ext=".tar.gz"
    fi

    is_musl=false
    if [ "$os" = "linux" ]; then
      if [ -f /etc/alpine-release ]; then
        is_musl=true
      fi

      if command -v ldd >/dev/null 2>&1; then
        if ldd --version 2>&1 | grep -qi musl; then
          is_musl=true
        fi
      fi
    fi

    needs_baseline=false
    if [ "$arch" = "x64" ]; then
      if [ "$os" = "linux" ]; then
        if ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
          needs_baseline=true
        fi
      fi

      if [ "$os" = "darwin" ]; then
        avx2=$(sysctl -n hw.optional.avx2_0 2>/dev/null || echo 0)
        if [ "$avx2" != "1" ]; then
          needs_baseline=true
        fi
      fi

    fi

    target="$os-$arch"
    if [ "$needs_baseline" = "true" ]; then
      target="$target-baseline"
    fi
    if [ "$is_musl" = "true" ]; then
      target="$target-musl"
    fi

    filename="$APP-$target$archive_ext"


    if [ "$os" = "linux" ]; then
        if ! command -v tar >/dev/null 2>&1; then
             echo -e "${RED}Error: 'tar' is required but not installed.${NC}"
             exit 1
        fi
    else
        if ! command -v unzip >/dev/null 2>&1; then
            echo -e "${RED}Error: 'unzip' is required but not installed.${NC}"
            exit 1
        fi
    fi

    if [ -n "$requested_version" ]; then
        specific_version="${requested_version#v}"
        if [[ ! "$specific_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: --version requires a stable semantic version${NC}"
            exit 1
        fi
        base="$RELEASES/download/v${specific_version}"
    else
        base="$RELEASES/latest/download"
    fi
fi

print_message() {
    local level=$1
    local message=$2
    local color=""

    case $level in
        info) color="${NC}" ;;
        warning) color="${NC}" ;;
        error) color="${RED}" ;;
    esac

    echo -e "${color}${message}${NC}"
}

json_value() {
    local key=$1
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n 1
}

sha256() {
    local file=$1
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
        return
    fi
    print_message error "Error: sha256sum, shasum, or openssl is required."
    exit 1
}

resolve_release() {
    WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/datacode_install.XXXXXX")
    trap 'rm -rf "${WORK_DIR:-}"' EXIT

    curl -fsSL "$base/datacode-manifest.json" -o "$WORK_DIR/datacode-manifest.json"
    curl -fsSL "$base/datacode-checksums.txt" -o "$WORK_DIR/datacode-checksums.txt"

    local product
    product=$(json_value product < "$WORK_DIR/datacode-manifest.json")
    if [ "$product" != "DataCode Runtime" ]; then
        print_message error "Error: Invalid DataCode Runtime manifest identity."
        exit 1
    fi

    local version
    version=$(json_value version < "$WORK_DIR/datacode-manifest.json")
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_message error "Error: Invalid DataCode Runtime manifest version."
        exit 1
    fi
    if [ -n "${specific_version:-}" ] && [ "$version" != "$specific_version" ]; then
        print_message error "Error: Release version mismatch: requested $specific_version, manifest reports $version."
        exit 1
    fi
    specific_version=$version

    local block
    block=$(awk -v target="$target" '
        $0 ~ "\"target\"[[:space:]]*:[[:space:]]*\"" target "\"" { found=1 }
        found { print }
        found && /^[[:space:]]*}/ { exit }
    ' "$WORK_DIR/datacode-manifest.json")
    if [ -z "$block" ]; then
        print_message error "Error: DataCode Runtime manifest has no artifact for $target."
        exit 1
    fi

    local manifest_file
    manifest_file=$(printf '%s\n' "$block" | json_value file)
    local executable
    executable=$(printf '%s\n' "$block" | json_value executable)
    manifest_sha=$(printf '%s\n' "$block" | json_value sha256)
    if [ "$manifest_file" != "$filename" ] || [ "$executable" != "bin/datacode" ]; then
        print_message error "Error: Invalid DataCode Runtime artifact contract for $target."
        exit 1
    fi
    if [[ ! "$manifest_sha" =~ ^[0-9a-f]{64}$ ]]; then
        print_message error "Error: Invalid SHA-256 in DataCode Runtime manifest."
        exit 1
    fi

    local checksum_sha
    checksum_sha=$(awk -v file="$filename" '$2 == file { print $1 }' "$WORK_DIR/datacode-checksums.txt")
    if [ "$checksum_sha" != "$manifest_sha" ]; then
        print_message error "Error: DataCode Runtime checksum metadata does not match the manifest."
        exit 1
    fi
    url="$base/$filename"
}


check_version() {
    if [ -x "$INSTALL_DIR/datacode" ]; then
        installed_version=$("$INSTALL_DIR/datacode" --version 2>/dev/null || echo "")

        if [[ "$installed_version" != "$specific_version" ]]; then
            print_message info "${MUTED}Installed version: ${NC}$installed_version."
        else
            print_message info "${MUTED}Version ${NC}$specific_version${MUTED} already installed"
            exit 0
        fi
    fi
}


unbuffered_sed() {
    if echo | sed -u -e "" >/dev/null 2>&1; then
        sed -nu "$@"
    elif echo | sed -l -e "" >/dev/null 2>&1; then
        sed -nl "$@"
    else
        local pad="$(printf "\n%512s" "")"
        sed -ne "s/$/\\${pad}/" "$@"
    fi
}

print_progress() {
    local bytes="$1"
    local length="$2"
    [ "$length" -gt 0 ] || return 0

    local width=50
    local percent=$(( bytes * 100 / length ))
    [ "$percent" -gt 100 ] && percent=100
    local on=$(( percent * width / 100 ))
    local off=$(( width - on ))

    local filled=$(printf "%*s" "$on" "")
    filled=${filled// /■}
    local empty=$(printf "%*s" "$off" "")
    empty=${empty// /･}

    printf "\r${ORANGE}%s%s %3d%%${NC}" "$filled" "$empty" "$percent" >&4
}

download_with_progress() {
    local url="$1"
    local output="$2"

    if [ -t 2 ]; then
        exec 4>&2
    else
        exec 4>/dev/null
    fi

    local tmp_dir=${TMPDIR:-/tmp}
    local basename="${tmp_dir}/datacode_install_$$"
    local tracefile="${basename}.trace"

    rm -f "$tracefile"
    mkfifo "$tracefile"

    # Hide cursor
    printf "\033[?25l" >&4

    trap "trap - RETURN; rm -f \"$tracefile\"; printf '\033[?25h' >&4; exec 4>&-" RETURN

    (
        curl --trace-ascii "$tracefile" -fsL -o "$output" "$url" 
    ) &
    local curl_pid=$!

    unbuffered_sed \
        -e 'y/ACDEGHLNORTV/acdeghlnortv/' \
        -e '/^0000: content-length:/p' \
        -e '/^<= recv data/p' \
        "$tracefile" | \
    {
        local length=0
        local bytes=0

        while IFS=" " read -r -a line; do
            [ "${#line[@]}" -lt 2 ] && continue
            local tag="${line[0]} ${line[1]}"

            if [ "$tag" = "0000: content-length:" ]; then
                length="${line[2]}"
                length=$(echo "$length" | tr -d '\r')
                bytes=0
            elif [ "$tag" = "<= recv" ]; then
                local size="${line[3]}"
                bytes=$(( bytes + size ))
                if [ "$length" -gt 0 ]; then
                    print_progress "$bytes" "$length"
                fi
            fi
        done
    }

    wait $curl_pid
    local ret=$?
    echo "" >&4
    return $ret
}

download_and_install() {
    print_message info "\n${MUTED}Installing ${NC}DataCode ${MUTED}version: ${NC}$specific_version"
    local archive="$WORK_DIR/$filename"
    local extract="$WORK_DIR/extract"
    mkdir -p "$extract"

    if ! [ -t 2 ] || ! download_with_progress "$url" "$archive"; then
        # Fallback to standard curl in non-TTY environments or if custom progress fails.
        curl -f# -L -o "$archive" "$url"
    fi

    local actual
    actual=$(sha256 "$archive")
    if [ "$actual" != "$manifest_sha" ]; then
        print_message error "Error: SHA-256 mismatch for $filename."
        exit 1
    fi

    local entries
    if [ "$os" = "linux" ]; then
        entries=$(tar -tzf "$archive")
    else
        entries=$(unzip -Z1 "$archive")
    fi
    if printf '%s\n' "$entries" | grep -Eq '(^/|(^|/)\.\.(/|$))'; then
        print_message error "Error: Unsafe path in DataCode Runtime archive."
        exit 1
    fi

    if [ "$os" = "linux" ]; then
        tar -xzf "$archive" -C "$extract"
    else
        unzip -q "$archive" -d "$extract"
    fi
    if [ ! -f "$extract/bin/datacode" ]; then
        print_message error "Error: DataCode Runtime archive is missing bin/datacode."
        exit 1
    fi

    local next="$INSTALL_DIR/.datacode.new.$$"
    cp "$extract/bin/datacode" "$next"
    chmod 755 "$next"

    if [ -d "$extract/tree-sitter" ]; then
        local trees="$INSTALL_DIR/.tree-sitter.new.$$"
        rm -rf "$trees"
        cp -R "$extract/tree-sitter" "$trees"
        rm -rf "$INSTALL_DIR/tree-sitter"
        mv "$trees" "$INSTALL_DIR/tree-sitter"
    fi
    if [ -f "$extract/LICENSE" ]; then
        cp "$extract/LICENSE" "$INSTALL_DIR/LICENSE"
    fi

    mv "$next" "$INSTALL_DIR/datacode"
}

install_from_binary() {
    print_message info "\n${MUTED}Installing ${NC}DataCode ${MUTED}from: ${NC}$binary_path"
    local next="$INSTALL_DIR/.datacode.new.$$"
    cp "$binary_path" "$next"
    chmod 755 "$next"
    mv "$next" "$INSTALL_DIR/datacode"
}

if [ -n "$binary_path" ]; then
    install_from_binary
else
    resolve_release
    check_version
    download_and_install
fi


add_to_path() {
    local config_file=$1
    local command=$2

    if grep -Fxq "$command" "$config_file"; then
        print_message info "Command already exists in $config_file, skipping write."
    elif [[ -w $config_file ]]; then
        echo -e "\n# datacode" >> "$config_file" 
        echo "$command" >> "$config_file"
        print_message info "${MUTED}Successfully added ${NC}datacode ${MUTED}to \$PATH in ${NC}$config_file" 
    else
        print_message warning "Manually add the directory to $config_file (or similar):"
        print_message info "  $command"
    fi
}

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}

current_shell=$(basename "${SHELL:-sh}")
case $current_shell in
    fish)
        config_files="$HOME/.config/fish/config.fish"
    ;;
    zsh)
        config_files="${ZDOTDIR:-$HOME}/.zshrc ${ZDOTDIR:-$HOME}/.zshenv $XDG_CONFIG_HOME/zsh/.zshrc $XDG_CONFIG_HOME/zsh/.zshenv"
    ;;
    bash)
        config_files="$HOME/.bashrc $HOME/.bash_profile $HOME/.profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
    ;;
    ash)
        config_files="$HOME/.ashrc $HOME/.profile /etc/profile"
    ;;
    sh)
        config_files="$HOME/.ashrc $HOME/.profile /etc/profile"
    ;;
    *)
        # Default case if none of the above matches
        config_files="$HOME/.bashrc $HOME/.bash_profile $XDG_CONFIG_HOME/bash/.bashrc $XDG_CONFIG_HOME/bash/.bash_profile"
    ;;
esac

if [[ "$no_modify_path" != "true" ]]; then
    config_file=""
    for file in $config_files; do
        if [[ -f $file ]]; then
            config_file=$file
            break
        fi
    done

    if [[ -z $config_file ]]; then
        print_message warning "No config file found for $current_shell. You may need to manually add to PATH:"
        print_message info "  export PATH=$INSTALL_DIR:\$PATH"
    elif [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        case $current_shell in
            fish)
                add_to_path "$config_file" "fish_add_path $INSTALL_DIR"
            ;;
            zsh)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            bash)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            ash)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            sh)
                add_to_path "$config_file" "export PATH=$INSTALL_DIR:\$PATH"
            ;;
            *)
                export PATH=$INSTALL_DIR:$PATH
                print_message warning "Manually add the directory to $config_file (or similar):"
                print_message info "  export PATH=$INSTALL_DIR:\$PATH"
            ;;
        esac
    fi
fi

if [ -n "${GITHUB_ACTIONS-}" ] && [ "${GITHUB_ACTIONS}" == "true" ]; then
    echo "$INSTALL_DIR" >> "$GITHUB_PATH"
    print_message info "Added $INSTALL_DIR to \$GITHUB_PATH"
fi


echo -e ""
echo -e "${ORANGE}DataCode${NC} ${MUTED}$specific_version installed successfully.${NC}"
echo -e ""
echo -e "cd <project>  ${MUTED}# Open directory${NC}"
echo -e "datacode      ${MUTED}# Start DataCode${NC}"
echo -e ""
echo -e "${MUTED}Installed at ${NC}$INSTALL_DIR/datacode"
echo -e ""
