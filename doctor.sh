#!/usr/bin/env bash
# doctor.sh - Diagnostic script for Godot Nakama development environment

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Dynamic check counter: every reported check increments this automatically.
CHECK_COUNT=0

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
    if $VERBOSE; then
        echo -e "[doctor] $*"
    fi
}

info_status() {
    # Keep the legacy first argument in existing calls for easy maintenance,
    # but number checks from the actual execution order instead.
    CHECK_COUNT=$((CHECK_COUNT + 1))

    local check_num="$CHECK_COUNT"
    local message="$2"
    local status_type="$3" # ok, warn, error
    local detail="${4:-}"

    case "$status_type" in
        ok)
            echo -e "[doctor] [${check_num}] ${message}... ${GREEN}OK${NC}${detail:+ ($detail)}"
            ;;
        warn)
            echo -e "[doctor] [${check_num}] ${message}... ${YELLOW}WARNING${NC}${detail:+ ($detail)}" >&2
            ;;
        error)
            echo -e "[doctor] [${check_num}] ${message}... ${RED}ERROR${NC}${detail:+ ($detail)}" >&2
            ;;
    esac
}

fail=0

# ==========================================
# 1. Audio, Video & Input Devices (Monitor, Keyboard, Mouse)
# ==========================================

# Check: Display variables for GUI
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    info_status "" "Checking display variables" "warn" "neither DISPLAY nor WAYLAND_DISPLAY set; this environment requires a graphical Linux/WSLg host or a supported display bridge"
else
    info_status "" "Checking display variables" "ok" "DISPLAY=${DISPLAY:-unset}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
fi

# Check: Monitor / Screen device access
if [[ -d /sys/class/drm ]] && ls /sys/class/drm/card*-* >/dev/null 2>&1; then
    active_monitors=$(ls /sys/class/drm/card*-* 2>/dev/null | grep -E "status$" | xargs grep -l "connected" 2>/dev/null | wc -l || echo "1")
    info_status "" "Checking monitor access" "ok" "active display outputs detected ($active_monitors)"
elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    info_status "" "Checking monitor access" "ok" "display server session active"
else
    info_status "" "Checking monitor access" "warn" "no active monitor DRM nodes or display session found"
fi

# Check: Keyboard device access
if [[ -f /.dockerenv ]] && [[ ! -d /dev/input ]]; then
    info_status "" "Checking keyboard access" "ok" "isolated container (input nodes not exposed)"
elif ls /dev/input/by-id/*kbd* >/dev/null 2>&1 || find /dev/input/ -name "event*" 2>/dev/null | head -n 1 | grep -q .; then
    info_status "" "Checking keyboard access" "ok" "keyboard input devices found in /dev/input"
else
    info_status "" "Checking keyboard access" "warn" "no standard keyboard input nodes accessible"
fi

# Check: Mouse / Pointer device access
if [[ -f /.dockerenv ]] && [[ ! -d /dev/input ]]; then
    info_status "" "Checking mouse access" "ok" "isolated container (input nodes not exposed)"
elif ls /dev/input/by-id/*mouse* >/dev/null 2>&1 || ls /dev/input/by-id/*event-mouse* >/dev/null 2>&1 || find /dev/input/ -name "event*" 2>/dev/null | head -n 1 | grep -q .; then
    info_status "" "Checking mouse access" "ok" "mouse/pointer input devices found"
else
    info_status "" "Checking mouse access" "warn" "no standard mouse input nodes accessible"
fi

# Check: GPU device access
if [[ -c /dev/dxg ]]; then
    info_status "" "Checking GPU access" "ok" "/dev/dxg exists (WSLg)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "" "Checking GPU access" "ok" "NVIDIA devices found"
else
    info_status "" "Checking GPU access" "warn" "no obvious GPU device nodes found"
fi

# Check: NVIDIA drivers
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "NVIDIA GPU")
    info_status "" "Checking NVIDIA drivers" "ok" "$gpu_name (nvidia-smi found)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "" "Checking NVIDIA drivers" "warn" "NVIDIA devices exist, but nvidia-smi is missing"
else
    info_status "" "Checking NVIDIA drivers" "ok" "not applicable (no NVIDIA hardware)"
fi

# Check: Vulkan API
if command -v vulkaninfo >/dev/null 2>&1; then
    if timeout 10s vulkaninfo --summary >/dev/null 2>&1; then
        info_status "" "Checking Vulkan API" "ok" "Vulkan API initialized successfully"
    else
        vulkan_status=$?

        if (( vulkan_status == 124 || vulkan_status == 137 )); then
            info_status "" "Checking Vulkan API" "warn" \
                "vulkaninfo timed out after 10 seconds; continuing diagnostics"
        else
            info_status "" "Checking Vulkan API" "error" \
                "vulkaninfo failed (exit code $vulkan_status; possible driver issue or missing dependency)"
            fail=1
        fi
    fi
else
    if command -v ldconfig >/dev/null 2>&1 && ldconfig -p | grep -q "libvulkan.so"; then
        info_status "" "Checking Vulkan API" "ok" \
            "libvulkan found (vulkaninfo not installed to verify init)"
    else
        info_status "" "Checking Vulkan API" "warn" \
            "Vulkan libraries not found. Godot may crash or fallback to software rendering"
    fi
fi

# Check: Video group permissions (Hardware Acceleration)
if [[ -f /.dockerenv ]]; then
    info_status "" "Checking video group permissions" "ok" "isolated container (skipping host group check)"
elif command -v groups >/dev/null 2>&1; then
    user_groups=$(groups)
    if echo "$user_groups" | grep -q -E "\bvideo\b|\brender\b"; then
        info_status "" "Checking video group permissions" "ok" "user belongs to 'video' or 'render' group"
    elif [[ -c /dev/dxg ]]; then
        info_status "" "Checking video group permissions" "ok" "WSLg detected (standard group check bypassed)"
    else
        info_status "" "Checking video group permissions" "warn" "user not in 'video' or 'render' group. Run: sudo usermod -aG render \$USER"
    fi
else
    info_status "" "Checking video group permissions" "ok" "skipped"
fi

# Check: Audio server (PulseAudio socket via WSLg)
pulse_socket="${PULSE_SERVER:-}"
pulse_socket="${pulse_socket#unix:}"
if [[ -n "${PULSE_SERVER:-}" && -S "$pulse_socket" ]]; then
    info_status "" "Checking audio device" "ok" "PulseAudio socket active ($pulse_socket)"
elif [[ -n "${PULSE_SERVER:-}" ]]; then
    info_status "" "Checking audio device" "warn" "PULSE_SERVER set but socket not found at $pulse_socket"
else
    info_status "" "Checking audio device" "warn" "PULSE_SERVER environment variable not set"
fi


# ==========================================
# 1.1 Project Permissions, Disk Space, Filesystem & System Limits
# ==========================================

# Check: Write permissions recursively in current directory
if [[ -w "." ]]; then
    unwritable_items=$(find . -maxdepth 7 -not -path './.git*' ! -writable 2>/dev/null | head -n 5 || true)
    if [[ -n "$unwritable_items" ]]; then
        info_status "" "Checking project write permissions" "warn" "some files/folders are not writable (possible root ownership from docker)"
        log "Unwritable items found:\n$unwritable_items"
    else
        info_status "" "Checking project write permissions" "ok" "fully writable (recursive)"
    fi
else
    info_status "" "Checking project write permissions" "error" "current directory is not writable"
    fail=1
fi

# Check: Available disk space
if command -v df >/dev/null 2>&1; then
    free_space_kb=$(df -k . | awk 'NR==2 {print $4}')
    free_space_gb=$(( free_space_kb / 1024 / 1024 ))
    if (( free_space_gb < 5 )); then
        info_status "" "Checking available disk space" "warn" "low space: ${free_space_gb}GB remaining"
    else
        info_status "" "Checking available disk space" "ok" "${free_space_gb}GB available"
    fi
else
    info_status "" "Checking available disk space" "warn" "df command not found"
fi

# Check: Project filesystem location
current_path="$(pwd)"
if [[ "$current_path" == /mnt/* ]]; then
    info_status "" "Checking project filesystem location" "warn" "located in Windows mount (/mnt/), performance may be degraded"
else
    info_status "" "Checking project filesystem location" "ok" "native Linux filesystem"
fi

# Check: Open file descriptors limit (nofile)
if command -v ulimit >/dev/null 2>&1; then
    nofile_limit=$(ulimit -n)
    if [[ "$nofile_limit" != "unlimited" ]] && (( nofile_limit < 4096 )); then
        info_status "" "Checking open file descriptors limit" "warn" "low limit ($nofile_limit), potential 'Too many open files' issues"
    else
        info_status "" "Checking open file descriptors limit" "ok" "limit is $nofile_limit"
    fi
else
    info_status "" "Checking open file descriptors limit" "warn" "ulimit not available"
fi

# Check: Total RAM allocation
if command -v free >/dev/null 2>&1; then
    ram_total_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if (( ram_total_mb < 3800 )); then
        info_status "" "Checking total RAM" "warn" "low RAM allocated (${ram_total_mb}MB), builds may run out of memory"
    else
        info_status "" "Checking total RAM" "ok" "${ram_total_mb}MB allocated"
    fi
else
    info_status "" "Checking total RAM" "warn" "free command not found"
fi

# Check: Swap memory availability
if command -v free >/dev/null 2>&1; then
    swap_total_kb=$(free -k | awk '/^Swap:/ {print $2}')
    if [[ -n "$swap_total_kb" ]] && (( swap_total_kb == 0 )); then
        info_status "" "Checking Swap memory" "warn" "no swap configured, risk of OOM kills under high load"
    else
        swap_total_mb=$(( swap_total_kb / 1024 ))
        info_status "" "Checking Swap memory" "ok" "${swap_total_mb}MB swap available"
    fi
else
    info_status "" "Checking Swap memory" "warn" "free command not found"
fi

# Check: System clock synchronization
if command -v timedatectl >/dev/null 2>&1 && timedatectl status >/dev/null 2>&1; then
    if timedatectl status | grep -E -i "synchronized: yes|NTP service: active" >/dev/null 2>&1; then
        info_status "" "Checking clock synchronization" "ok" "system clock synchronized"
    else
        info_status "" "Checking clock synchronization" "warn" "clock not marked as synchronized"
    fi
elif [[ -f /.dockerenv ]]; then
    info_status "" "Checking clock synchronization" "ok" "managed by host container engine"
else
    remote_date=$(curl -sI --max-time 3 https://github.com 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- || true)
    if [[ -n "$remote_date" ]]; then
        remote_sec=$(date -d "$remote_date" +%s 2>/dev/null || echo 0)
        local_sec=$(date +%s)
        diff_sec=$(( local_sec > remote_sec ? local_sec - remote_sec : remote_sec - local_sec ))
        if (( diff_sec < 15 )); then
            info_status "" "Checking clock synchronization" "ok" "clock aligned (drift: ${diff_sec}s)"
        else
            info_status "" "Checking clock synchronization" "warn" "clock drift detected (${diff_sec}s skew)"
        fi
    else
        info_status "" "Checking clock synchronization" "warn" "unable to verify time status"
    fi
fi

# Check: Systemd / init system
if [[ -f /.dockerenv ]]; then
    info_status "" "Checking systemd init system" "ok" "running inside Docker container (PID 1: $(ps -p 1 -o comm= 2>/dev/null || echo 'docker-init'))"
elif [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]] || [[ -d /run/systemd/system ]]; then
    systemd_version=$(systemctl --version 2>/dev/null | head -n1 || echo "systemd active")
    info_status "" "Checking systemd init system" "ok" "$systemd_version"
else
    info_status "" "Checking systemd init system" "warn" "systemd is not running as PID 1 (run 'wsl --shutdown' in PowerShell if recently enabled)"
fi


# ==========================================
# 2. Local Port Availability & Conflicts
# ==========================================

# Checks: Critical ports (5432, 7350, 7349)
for port_info in "5432:PostgreSQL" "7350:Nakama Client" "7349:Nakama gRPC"; do
    IFS=':' read -r port name <<< "$port_info"
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        info_status "" "Checking port $port ($name)" "ok" "port in use (active container or local service)"
    else
        info_status "" "Checking port $port ($name)" "ok" "port free"
    fi
done

# Check: Local Firewall (UFW)
if command -v ufw >/dev/null 2>&1; then
    if sudo -n ufw status >/dev/null 2>&1; then
        ufw_status=$(sudo -n ufw status | grep "Status" | awk '{print $2}')
        if [[ "${ufw_status,,}" == "active" ]]; then
            info_status "" "Checking local Firewall (UFW)" "warn" "UFW is ACTIVE. Ensure UDP port 7350 is explicitly allowed for multiplayer"
        else
            info_status "" "Checking local Firewall (UFW)" "ok" "UFW is inactive (no blocking rules)"
        fi
    else
        info_status "" "Checking local Firewall (UFW)" "ok" "installed but requires sudo to check status (assuming OK)"
    fi
else
    info_status "" "Checking local Firewall (UFW)" "ok" "not installed"
fi


# ==========================================
# 3. Languages & Tools
# ==========================================

# Check: CMake
if ! command -v cmake >/dev/null 2>&1; then
    info_status "" "Checking CMake" "warn" "not found in PATH"
else
    cmake_version=$(cmake --version | head -n1)
    info_status "" "Checking CMake" "ok" "$cmake_version"
fi

# Check: Clang
if ! command -v clang >/dev/null 2>&1; then
    info_status "" "Checking Clang" "warn" "not found in PATH"
else
    clang_version=$(clang --version | head -n1)
    info_status "" "Checking Clang" "ok" "$clang_version"
fi

# Check: G++
if ! command -v g++ >/dev/null 2>&1; then
    info_status "" "Checking G++" "warn" "not found in PATH"
else
    gxx_version=$(g++ --version | head -n1)
    info_status "" "Checking G++" "ok" "$gxx_version"
fi

# Check: .NET SDK version against global.json
if ! command -v dotnet >/dev/null 2>&1; then
    info_status "" "Checking .NET SDK" "error" "CLI not found"
    fail=1
else
    dotnet_version=$(dotnet --version)
    if [[ -f global.json ]]; then
        expected_version=$(jq -r '.sdk.version // empty' global.json 2>/dev/null || true)
        if [[ -n "$expected_version" ]]; then
            if [[ "$dotnet_version" != "$expected_version"* ]]; then
                info_status "" "Checking .NET SDK" "warn" "expected $expected_version, got $dotnet_version"
            else
                info_status "" "Checking .NET SDK" "ok" "version $dotnet_version"
            fi
        else
            info_status "" "Checking .NET SDK" "ok" "version $dotnet_version (no global.json version constraint)"
        fi
    else
        info_status "" "Checking .NET SDK" "ok" "version $dotnet_version (global.json not found)"
    fi
fi

# Check: Installed .NET Runtimes
if ! command -v dotnet >/dev/null 2>&1; then
    info_status "" "Checking .NET Runtimes" "error" "dotnet CLI not found"
    fail=1
else
    runtimes_list=$(dotnet --list-runtimes 2>/dev/null || true)
    if [[ -n "$runtimes_list" ]]; then
        runtime_summary=$(echo "$runtimes_list" | awk '{print $1 " " $2}' | paste -sd, -)
        info_status "" "Checking .NET Runtimes" "ok" "$runtime_summary"
        log "Installed runtimes:\n$runtimes_list"
    else
        info_status "" "Checking .NET Runtimes" "warn" "no runtimes found via dotnet --list-runtimes"
    fi
fi

# Check: csharpier
if command -v dotnet-csharpier >/dev/null 2>&1 || dotnet csharpier --version >/dev/null 2>&1 || [[ -f /workspaces/.dotnet/tools/dotnet-csharpier ]]; then
    csharpier_version=$(dotnet-csharpier --version 2>/dev/null || /workspaces/.dotnet/tools/dotnet-csharpier --version 2>/dev/null | head -n1 || echo "installed")
    info_status "" "Checking csharpier" "ok" "$csharpier_version"
else
    info_status "" "Checking csharpier" "warn" "not found in PATH or ~/.dotnet/tools. Review tasks.json (.NET: Restore Tools)."
fi

# Check: dotnet-trace
trace_binary="$(command -v dotnet-trace || true)"

if [[ -z "$trace_binary" && -x "$HOME/.dotnet/tools/dotnet-trace" ]]; then
    trace_binary="$HOME/.dotnet/tools/dotnet-trace"
fi

if [[ -n "$trace_binary" ]]; then
    trace_version=$("$trace_binary" --version 2>/dev/null | head -n1 || echo "installed")
    info_status "" "Checking dotnet-trace" "ok" "$trace_version"
else
    info_status "" "Checking dotnet-trace" "warn" \
        "not found in PATH or $HOME/.dotnet/tools. Review tasks.json (.NET: Install Profiler)."
fi

# Check: Go
if ! command -v go >/dev/null 2>&1; then
    info_status "" "Checking Go" "error" "not found"
    fail=1
else
    go_version=$(go version)
    info_status "" "Checking Go" "ok" "$go_version"
fi

# Check: Godot editor
if ! command -v godot >/dev/null 2>&1; then
    info_status "" "Checking Godot editor" "error" "not found in PATH"
    fail=1
else
    godot_version=$(godot --version | head -n1)
    info_status "" "Checking Godot editor" "ok" "$godot_version"
fi

# Check: Godot Vulkan rendering
if command -v godot >/dev/null 2>&1; then
    if timeout 20s godot --rendering-driver vulkan --headless --editor --quit >/dev/null 2>&1; then
        info_status "" "Checking Godot Vulkan rendering" "ok" \
            "headless Vulkan initialization succeeded"
    else
        godot_vulkan_status=$?

        if (( godot_vulkan_status == 124 || godot_vulkan_status == 137 )); then
            info_status "" "Checking Godot Vulkan rendering" "warn" \
                "Godot Vulkan initialization timed out after 20 seconds"
        else
            info_status "" "Checking Godot Vulkan rendering" "warn" \
                "failed to initialize Vulkan renderer in headless mode (exit code $godot_vulkan_status)"
        fi
    fi
else
    info_status "" "Checking Godot Vulkan rendering" "warn" \
        "skipped (Godot binary not found)"
fi

# Check: Aseprite
if ! command -v aseprite >/dev/null 2>&1; then
    info_status "" "Checking Aseprite" "error" "not found in PATH"
    fail=1
else
    if aseprite_output=$(timeout 5s aseprite --version 2>&1); then
        aseprite_version="${aseprite_output%%$'\n'*}"

        if [[ -z "$aseprite_version" ]]; then
            aseprite_version="installed (version unavailable)"
        fi

        info_status "" "Checking Aseprite" "ok" "$aseprite_version"
    else
        aseprite_status=$?

        if (( aseprite_status == 124 || aseprite_status == 137 )); then
            info_status "" "Checking Aseprite" "warn" \
                "aseprite --version timed out after 5 seconds"
        else
            info_status "" "Checking Aseprite" "warn" \
                "aseprite --version failed (exit code $aseprite_status)"
        fi
    fi
fi

# Check: GIMP
if ! command -v gimp >/dev/null 2>&1; then
    info_status "" "Checking GIMP" "error" "not found in PATH"
    fail=1
else
    if gimp_output=$(timeout 5s gimp --version 2>&1); then
        gimp_version="${gimp_output%%$'\n'*}"

        if [[ -z "$gimp_version" ]]; then
            gimp_version="installed (version unavailable)"
        fi

        info_status "" "Checking GIMP" "ok" "$gimp_version"
    else
        gimp_status=$?

        if (( gimp_status == 124 || gimp_status == 137 )); then
            info_status "" "Checking GIMP" "warn" \
                "gimp --version timed out after 5 seconds"
        else
            info_status "" "Checking GIMP" "warn" \
                "gimp --version failed (exit code $gimp_status)"
        fi
    fi
fi

# Check: Inochi Creator
inochi_path=""

if command -v inochi-creator >/dev/null 2>&1; then
    inochi_path="$(command -v inochi-creator)"
elif [[ -x /opt/inochi-creator/inochi-creator ]]; then
    inochi_path="/opt/inochi-creator/inochi-creator"
fi

if [[ -n "$inochi_path" ]]; then
    info_status "" "Checking Inochi Creator" "ok" \
        "executable available ($inochi_path; startup not tested)"
else
    info_status "" "Checking Inochi Creator" "error" \
        "not found in PATH or /opt/inochi-creator"
    fail=1
fi

# Check: Git
if ! command -v git >/dev/null 2>&1; then
    info_status "" "Checking Git" "error" "not found in PATH"
    fail=1
else
    git_version=$(git --version | head -n1)
    info_status "" "Checking Git" "ok" "$git_version"
fi

# Check: Git repository status
if command -v git >/dev/null 2>&1; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git branch --show-current 2>/dev/null)
        if [[ -z "$git_branch" ]]; then
            git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
        fi
        git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        info_status "" "Checking Git repository" "ok" "branch: $git_branch, commit: $git_hash"
    else
        info_status "" "Checking Git repository" "warn" "current directory is not a git repository"
    fi
else
    info_status "" "Checking Git repository" "warn" "git not found"
fi

# Check: Git LFS
if ! command -v git >/dev/null 2>&1 || ! git lfs version >/dev/null 2>&1; then
    info_status "" "Checking Git LFS" "error" "not found"
    fail=1
else
    lfs_version=$(git lfs version | head -n1)
    if ! git lfs env | grep -q "Local"; then
        info_status "" "Checking Git LFS" "warn" "may not be properly installed"
    else
        info_status "" "Checking Git LFS" "ok" "$lfs_version"
    fi
fi

# Check: Git LFS integrity (pending binary downloads)
if command -v git >/dev/null 2>&1 && git lfs version >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git lfs ls-files 2>&1 | grep -q '^-'; then
        info_status "" "Checking Git LFS integrity" "error" "missing binary files detected (run 'git lfs pull')"
        fail=1
    else
        info_status "" "Checking Git LFS integrity" "ok" "all LFS files downloaded"
    fi
else
    info_status "" "Checking Git LFS integrity" "ok" "skipped"
fi

# Check: GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    info_status "" "Checking GitHub CLI" "error" "not found"
    fail=1
else
    gh_version=$(gh --version | head -n1)
    if ! gh auth status >/dev/null 2>&1; then
        info_status "" "Checking GitHub CLI" "warn" "not authenticated - run 'gh auth login'"
    else
        info_status "" "Checking GitHub CLI" "ok" "$gh_version"
    fi
fi


# ==========================================
# 4. Docker & Docker Compose
# ==========================================

# Check: Docker CLI
if ! command -v docker >/dev/null 2>&1; then
    info_status "" "Checking Docker" "error" "not found in PATH"
    fail=1
else
    info_status "" "Checking Docker" "ok" "CLI available"
fi

# Check: Docker daemon
if ! command -v docker >/dev/null 2>&1; then
    info_status "" "Checking Docker daemon" "error" "skipped"
    fail=1
else
    if docker info >/dev/null 2>&1; then
        info_status "" "Checking Docker daemon" "ok" "accessible"
    else
        info_status "" "Checking Docker daemon" "error" "not accessible"
        fail=1
    fi
fi

# Check: Docker socket access inside container
if [[ -f /.dockerenv ]]; then
    if [[ -S /var/run/docker.sock ]] && docker ps >/dev/null 2>&1; then
        info_status "" "Checking Docker socket access" "ok" "socket mounted and accessible"
    elif [[ -S /var/run/docker.sock ]]; then
        info_status "" "Checking Docker socket access" "warn" "socket mounted but permission denied"
    else
        info_status "" "Checking Docker socket access" "ok" "isolated container (no host socket mounted)"
    fi
else
    info_status "" "Checking Docker socket access" "ok" "not in container (native host)"
fi

# Check: Docker Compose
if ! docker-compose version >/dev/null 2>&1; then
    info_status "" "Checking Docker Compose" "error" "plugin not found"
    fail=1
else
    info_status "" "Checking Docker Compose" "ok" "$(docker-compose version --short)"
fi

# ==========================================
# 5 & 6. Container Services & Backend Health
# ==========================================

# Find the Compose project from an existing container.
# We use Docker-compatible commands directly because Podman Compose
# containers are not always discovered correctly by Docker Compose.
COMPOSE_PROJECT_NAME=""

for container in nakama postgres rustfs godot; do
    candidate_project=$(
        docker inspect \
            --format '{{ index .Config.Labels "com.docker.compose.project" }}' \
            "$container" 2>/dev/null || true
    )

    if [[ -n "$candidate_project" && "$candidate_project" != "<no value>" ]]; then
        COMPOSE_PROJECT_NAME="$candidate_project"
        break
    fi
done

# Report the actual state of a container using the Docker-compatible API.
container_state() {
    local container="$1"

    if ! docker inspect "$container" >/dev/null 2>&1; then
        echo "missing"
    elif [[ "$(docker inspect --format '{{.State.Running}}' "$container" 2>/dev/null || true)" == "true" ]]; then
        echo "running"
    else
        echo "stopped"
    fi
}

# Check: Running containers for the detected project
if [[ -n "$COMPOSE_PROJECT_NAME" ]]; then
    running_services=$(
        docker ps \
            --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" \
            --format '{{.Label "com.docker.compose.service"}}' 2>/dev/null |
            grep -v '^$' | sort -u || true
    )
else
    # Fallback for containers that do not expose Compose project labels.
    running_services=$(
        docker ps --format '{{.Names}}' 2>/dev/null |
            grep -E '^(godot|postgres|rustfs|nakama)$' || true
    )
fi

if [[ -n "$running_services" ]]; then
    info_status "" "Checking Docker-compatible container services" "ok" \
        "running: $(echo "$running_services" | paste -sd ', ' -)"
else
    info_status "" "Checking Docker-compatible container services" "warn" \
        "no project containers are running"
fi

# Check: PostgreSQL container
postgres_state=$(container_state postgres)

case "$postgres_state" in
    running)
        info_status "" "Checking service 'postgres'" "ok" "running"
        ;;
    stopped)
        info_status "" "Checking service 'postgres'" "warn" \
            "container exists but is stopped"
        ;;
    *)
        info_status "" "Checking service 'postgres'" "warn" \
            "container not found"
        ;;
esac

# Check: Nakama container
nakama_state=$(container_state nakama)

case "$nakama_state" in
    running)
        info_status "" "Checking service 'nakama'" "ok" "running"
        ;;
    stopped)
        info_status "" "Checking service 'nakama'" "warn" \
            "container exists but is stopped"
        ;;
    *)
        info_status "" "Checking service 'nakama'" "warn" \
            "container not found"
        ;;
esac

# Check: PostgreSQL connectivity
if [[ "$postgres_state" == "running" ]] &&
   docker exec postgres pg_isready -U postgres -d nakama >/dev/null 2>&1; then
    info_status "" "Checking PostgreSQL connectivity" "ok" \
        "accepting connections"
else
    info_status "" "Checking PostgreSQL connectivity" "warn" \
        "not accepting connections"
fi

# Check: Nakama Client API (Port 7350)
if curl -s -f http://nakama:7350/healthcheck >/dev/null 2>&1 ||
   curl -s -f http://localhost:7350/healthcheck >/dev/null 2>&1; then
    info_status "" "Checking Nakama Client API (7350)" "ok" "responding"
else
    info_status "" "Checking Nakama Client API (7350)" "warn" \
        "not responding"
fi

# Check: Nakama gRPC API (Port 7349)
if curl -s --http2-prior-knowledge http://nakama:7349 >/dev/null 2>&1 ||
   nc -z nakama 7349 >/dev/null 2>&1 ||
   nc -z localhost 7349 >/dev/null 2>&1; then
    info_status "" "Checking Nakama gRPC API (7349)" "ok" "responding"
else
    info_status "" "Checking Nakama gRPC API (7349)" "warn" \
        "not responding"
fi

# Check: Nakama UDP API (Port 7350 - Realtime / Socket Routing)
if command -v nc >/dev/null 2>&1; then
    if echo "" | nc -u -w 1 localhost 7350 >/dev/null 2>&1 ||
       echo "" | nc -u -w 1 nakama 7350 >/dev/null 2>&1; then
        info_status "" "Checking Nakama UDP routing (7350)" "ok" \
            "UDP socket reachable"
    else
        info_status "" "Checking Nakama UDP routing (7350)" "warn" \
            "UDP port 7350 unreachable (check the port mapping)"
    fi
else
    info_status "" "Checking Nakama UDP routing (7350)" "warn" \
        "netcat (nc) not installed, skipping UDP test"
fi


# ==========================================
# 7. Workspace, Editors & Shell Utilities
# ==========================================

# Check: Workspace folder
if [[ -f GodotNakama.code-workspace ]]; then
    info_status "" "Checking workspace" "ok" "GodotNakama.code-workspace found"
else
    info_status "" "Checking workspace" "warn" "workspace file not found"
fi

# Check: VS Code
if ! command -v code >/dev/null 2>&1; then
    info_status "" "Checking VS Code" "warn" "not found in PATH"
else
    code_version=$(code --version | head -n1)
    info_status "" "Checking VS Code" "ok" "version $code_version"
fi

# Check: Nano
if ! command -v nano >/dev/null 2>&1; then
    info_status "" "Checking nano" "warn" "not found in PATH"
else
    nano_version=$(nano --version | head -n1)
    info_status "" "Checking nano" "ok" "$nano_version"
fi

# Check: Bash
if ! command -v bash >/dev/null 2>&1; then
    info_status "" "Checking bash" "error" "not found in PATH"
    fail=1
else
    bash_version=$(bash --version | head -n1)
    info_status "" "Checking bash" "ok" "$bash_version"
fi

# Check: Zsh
if ! command -v zsh >/dev/null 2>&1; then
    info_status "" "Checking zsh" "warn" "not found in PATH"
else
    zsh_version=$(zsh --version)
    info_status "" "Checking zsh" "ok" "$zsh_version"
fi

# Check: PowerShell
if command -v pwsh >/dev/null 2>&1; then
    pwsh_version=$(pwsh --version 2>/dev/null | head -n1 || echo "pwsh active")
    info_status "" "Checking PowerShell" "ok" "$pwsh_version"
elif command -v powershell.exe >/dev/null 2>&1; then
    info_status "" "Checking PowerShell" "ok" "powershell.exe available (Windows host)"
elif command -v powershell >/dev/null 2>&1; then
    ps_version=$(powershell --version 2>/dev/null | head -n1 || echo "powershell active")
    info_status "" "Checking PowerShell" "ok" "$ps_version"
else
    info_status "" "Checking PowerShell" "warn" "not found in PATH"
fi

# Check: Tmux
if ! command -v tmux >/dev/null 2>&1; then
    info_status "" "Checking tmux" "error" "not found in PATH"
    fail=1
else
    tmux_version=$(tmux -V)
    info_status "" "Checking tmux" "ok" "$tmux_version"
fi


# ==========================================
# 8. External Connectivity & Network Health Checks
# ==========================================

# Check: DNS resolution performance
if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
        info_status "" "Checking DNS resolution" "ok" "resolving external hosts correctly"
    else
        info_status "" "Checking DNS resolution" "error" "unable to resolve external hosts"
        fail=1
    fi
else
    info_status "" "Checking DNS resolution" "warn" "getent command not found"
fi

# Check: Strict localhost resolution
if command -v getent >/dev/null 2>&1; then
    if getent ahosts localhost | grep -qE "^127\.|^::1"; then
        resolved_ips=$(getent ahosts localhost | awk '{print $1}' | sort -u | paste -sd, -)
        info_status "" "Checking localhost resolution" "ok" "resolves to local loopback ($resolved_ips)"
    else
        info_status "" "Checking localhost resolution" "error" "localhost does not resolve to 127.x.x.x or ::1 (check /etc/hosts)"
        fail=1
    fi
else
    info_status "" "Checking localhost resolution" "warn" "getent command not found, skipping check"
fi

# Check: GitHub (Git Push/Pull & APIs)
if curl -s --max-time 5 https://github.com >/dev/null 2>&1; then
    info_status "" "Checking GitHub reachability" "ok" "reachable"
else
    info_status "" "Checking GitHub reachability" "warn" "unreachable (git push/pull might fail)"
fi

# Check: NuGet Package Feed (C# Package Restore)
if curl -s --max-time 5 https://api.nuget.org/v3/index.json >/dev/null 2>&1; then
    info_status "" "Checking NuGet reachability" "ok" "reachable"
else
    info_status "" "Checking NuGet reachability" "warn" "unreachable (dotnet restore might fail)"
fi

# Check: Docker Hub (Pulling images)
if curl -s --max-time 5 https://registry-1.docker.io/v2/ >/dev/null 2>&1; then
    info_status "" "Checking Docker Hub reachability" "ok" "reachable"
else
    info_status "" "Checking Docker Hub reachability" "warn" "unreachable (docker pull might fail)"
fi

# Check: Godot Engine (Assets & Asset Library)
if curl -s --max-time 5 https://godotengine.org >/dev/null 2>&1; then
    info_status "" "Checking Godot Engine reachability" "ok" "reachable"
else
    info_status "" "Checking Godot Engine reachability" "warn" "unreachable (asset library might fail)"
fi

# Check: Backtrace (Bug reporting)
if curl -s --max-time 5 https://backtrace.io >/dev/null 2>&1; then
    info_status "" "Checking Backtrace reachability" "ok" "reachable"
else
    info_status "" "Checking Backtrace reachability" "warn" "unreachable (errors won't show up in Backtrace panel)"
fi

# Check: Godot Asset Library API (store.godotengine.org)
if curl -s --max-time 5 https://store.godotengine.org/api/v1 >/dev/null 2>&1; then
    info_status "" "Checking Godot Asset Library API reachability" "ok" "reachable"
else
    info_status "" "Checking Godot Asset Library API reachability" "warn" "unreachable (fetching/downloading assets from store might fail)"
fi

# Check: Godot Export Templates
export_templates_dir="${HOME}/.local/share/godot/export_templates"
if [[ -d "$export_templates_dir" ]] && find "$export_templates_dir" -type f \( -name "*.tpz" -o -name "linuxbsd_*" -o -name "windows_*" -o -name "android_*" \) -print -quit | grep -q .; then
    templates_count=$(find "$export_templates_dir" -type f \( -name "*.tpz" -o -name "linuxbsd_*" -o -name "windows_*" -o -name "android_*" \) | wc -l)
    info_status "" "Checking Godot Export Templates" "ok" "$templates_count template files found"
else
    info_status "" "Checking Godot Export Templates" "warn" "no export templates found in $export_templates_dir"
fi

if (( fail > 0 )); then
    echo -e "\n${RED}[doctor] Diagnostic completed with errors (${fail} failure(s)).${NC}"
    exit 1
else
    echo -e "\n${GREEN}[doctor] All critical checks passed successfully!${NC}"
    exit 0
fi
