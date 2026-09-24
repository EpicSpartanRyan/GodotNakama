#!/usr/bin/env bash
# doctor.sh - Diagnostic script for Godot Nakama development environment

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

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
    local check_num="$1"
    local message="$2"
    local status_type="$3" # ok, warn, error
    local detail="$4"

    case "$status_type" in
        ok)
            echo -e "[doctor] [$check_num/60] ${message}... ${GREEN}OK${NC}${detail:+ ($detail)}"
            ;;
        warn)
            echo -e "[doctor] [$check_num/60] ${message}... ${YELLOW}WARNING${NC}${detail:+ ($detail)}" >&2
            ;;
        error)
            echo -e "[doctor] [$check_num/60] ${message}... ${RED}ERROR${NC}${detail:+ ($detail)}" >&2
            ;;
    esac
}

fail=0

# ==========================================
# 1. Audio, Video & Input Devices (Monitor, Keyboard, Mouse)
# ==========================================

# Check 1: Display variables for GUI
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    info_status "1" "Checking display variables" "warn" "neither DISPLAY nor WAYLAND_DISPLAY set"
else
    info_status "1" "Checking display variables" "ok" "DISPLAY=${DISPLAY:-unset}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
fi

# Check 2: Monitor / Screen device access
if [[ -d /sys/class/drm ]] && ls /sys/class/drm/card*-* >/dev/null 2>&1; then
    active_monitors=$(ls /sys/class/drm/card*-* 2>/dev/null | grep -E "status$" | xargs grep -l "connected" 2>/dev/null | wc -l || echo "1")
    info_status "2" "Checking monitor access" "ok" "active display outputs detected ($active_monitors)"
elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    info_status "2" "Checking monitor access" "ok" "display server session active"
else
    info_status "2" "Checking monitor access" "warn" "no active monitor DRM nodes or display session found"
fi

# Check 3: Keyboard device access
if [[ -f /.dockerenv ]] && [[ ! -d /dev/input ]]; then
    info_status "3" "Checking keyboard access" "ok" "isolated container (input nodes not exposed)"
elif ls /dev/input/by-id/*kbd* >/dev/null 2>&1 || find /dev/input/ -name "event*" 2>/dev/null | head -n 1 | grep -q .; then
    info_status "3" "Checking keyboard access" "ok" "keyboard input devices found in /dev/input"
else
    info_status "3" "Checking keyboard access" "warn" "no standard keyboard input nodes accessible"
fi

# Check 4: Mouse / Pointer device access
if [[ -f /.dockerenv ]] && [[ ! -d /dev/input ]]; then
    info_status "4" "Checking mouse access" "ok" "isolated container (input nodes not exposed)"
elif ls /dev/input/by-id/*mouse* >/dev/null 2>&1 || ls /dev/input/by-id/*event-mouse* >/dev/null 2>&1 || find /dev/input/ -name "event*" 2>/dev/null | head -n 1 | grep -q .; then
    info_status "4" "Checking mouse access" "ok" "mouse/pointer input devices found"
else
    info_status "4" "Checking mouse access" "warn" "no standard mouse input nodes accessible"
fi

# Check 5: GPU device access
if [[ -c /dev/dxg ]]; then
    info_status "5" "Checking GPU access" "ok" "/dev/dxg exists (WSLg)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "5" "Checking GPU access" "ok" "NVIDIA devices found"
else
    info_status "5" "Checking GPU access" "warn" "no obvious GPU device nodes found"
fi

# Check 6: NVIDIA drivers
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "NVIDIA GPU")
    info_status "6" "Checking NVIDIA drivers" "ok" "$gpu_name (nvidia-smi found)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "6" "Checking NVIDIA drivers" "warn" "NVIDIA devices exist, but nvidia-smi is missing"
else
    info_status "6" "Checking NVIDIA drivers" "ok" "not applicable (no NVIDIA hardware)"
fi

# Check 7: Vulkan API
if command -v vulkaninfo >/dev/null 2>&1; then
    if vulkaninfo --summary >/dev/null 2>&1; then
        info_status "7" "Checking Vulkan API" "ok" "Vulkan API initialized successfully"
    else
        info_status "7" "Checking Vulkan API" "error" "vulkaninfo failed to run (driver issues or missing dependencies)"
        fail=1
    fi
else
    if command -v ldconfig >/dev/null 2>&1 && ldconfig -p | grep -q "libvulkan.so"; then
        info_status "7" "Checking Vulkan API" "ok" "libvulkan found (vulkaninfo not installed to verify init)"
    else
        info_status "7" "Checking Vulkan API" "warn" "Vulkan libraries not found. Godot may crash or fallback to software rendering"
    fi
fi

# Check 8: Video group permissions (Hardware Acceleration)
if [[ -f /.dockerenv ]]; then
    info_status "8" "Checking video group permissions" "ok" "isolated container (skipping host group check)"
elif command -v groups >/dev/null 2>&1; then
    user_groups=$(groups)
    if echo "$user_groups" | grep -q -E "\bvideo\b|\brender\b"; then
        info_status "8" "Checking video group permissions" "ok" "user belongs to 'video' or 'render' group"
    elif [[ -c /dev/dxg ]]; then
        info_status "8" "Checking video group permissions" "ok" "WSLg detected (standard group check bypassed)"
    else
        info_status "8" "Checking video group permissions" "warn" "user not in 'video' or 'render' group. Run: sudo usermod -aG render \$USER"
    fi
else
    info_status "8" "Checking video group permissions" "ok" "skipped"
fi

# Check 9: Audio server (PulseAudio socket via WSLg)
pulse_socket="${PULSE_SERVER#unix:}"
if [[ -n "${PULSE_SERVER:-}" && -S "$pulse_socket" ]]; then
    info_status "9" "Checking audio device" "ok" "PulseAudio socket active ($pulse_socket)"
elif [[ -n "${PULSE_SERVER:-}" ]]; then
    info_status "9" "Checking audio device" "warn" "PULSE_SERVER set but socket not found at $pulse_socket"
else
    info_status "9" "Checking audio device" "warn" "PULSE_SERVER environment variable not set"
fi


# ==========================================
# 1.1 Project Permissions, Disk Space, Filesystem & System Limits
# ==========================================

# Check 10: Write permissions recursively in current directory
if [[ -w "." ]]; then
    unwritable_items=$(find . -maxdepth 7 -not -path './.git*' ! -writable 2>/dev/null | head -n 5 || true)
    if [[ -n "$unwritable_items" ]]; then
        info_status "10" "Checking project write permissions" "warn" "some files/folders are not writable (possible root ownership from docker)"
        log "Unwritable items found:\n$unwritable_items"
    else
        info_status "10" "Checking project write permissions" "ok" "fully writable (recursive)"
    fi
else
    info_status "10" "Checking project write permissions" "error" "current directory is not writable"
    fail=1
fi

# Check 11: Available disk space
if command -v df >/dev/null 2>&1; then
    free_space_kb=$(df -k . | awk 'NR==2 {print $4}')
    free_space_gb=$(( free_space_kb / 1024 / 1024 ))
    if (( free_space_gb < 5 )); then
        info_status "11" "Checking available disk space" "warn" "low space: ${free_space_gb}GB remaining"
    else
        info_status "11" "Checking available disk space" "ok" "${free_space_gb}GB available"
    fi
else
    info_status "11" "Checking available disk space" "warn" "df command not found"
fi

# Check 12: Project filesystem location
current_path="$(pwd)"
if [[ "$current_path" == /mnt/* ]]; then
    info_status "12" "Checking project filesystem location" "warn" "located in Windows mount (/mnt/), performance may be degraded"
else
    info_status "12" "Checking project filesystem location" "ok" "native Linux filesystem"
fi

# Check 13: Open file descriptors limit (nofile)
if command -v ulimit >/dev/null 2>&1; then
    nofile_limit=$(ulimit -n)
    if [[ "$nofile_limit" != "unlimited" ]] && (( nofile_limit < 4096 )); then
        info_status "13" "Checking open file descriptors limit" "warn" "low limit ($nofile_limit), potential 'Too many open files' issues"
    else
        info_status "13" "Checking open file descriptors limit" "ok" "limit is $nofile_limit"
    fi
else
    info_status "13" "Checking open file descriptors limit" "warn" "ulimit not available"
fi

# Check 14: Total RAM allocation
if command -v free >/dev/null 2>&1; then
    ram_total_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if (( ram_total_mb < 3800 )); then
        info_status "14" "Checking total RAM" "warn" "low RAM allocated (${ram_total_mb}MB), builds may run out of memory"
    else
        info_status "14" "Checking total RAM" "ok" "${ram_total_mb}MB allocated"
    fi
else
    info_status "14" "Checking total RAM" "warn" "free command not found"
fi

# Check 15: Swap memory availability
if command -v free >/dev/null 2>&1; then
    swap_total_kb=$(free -k | awk '/^Swap:/ {print $2}')
    if [[ -n "$swap_total_kb" ]] && (( swap_total_kb == 0 )); then
        info_status "15" "Checking Swap memory" "warn" "no swap configured, risk of OOM kills under high load"
    else
        swap_total_mb=$(( swap_total_kb / 1024 ))
        info_status "15" "Checking Swap memory" "ok" "${swap_total_mb}MB swap available"
    fi
else
    info_status "15" "Checking Swap memory" "warn" "free command not found"
fi

# Check 16: System clock synchronization
if command -v timedatectl >/dev/null 2>&1 && timedatectl status >/dev/null 2>&1; then
    if timedatectl status | grep -E -i "synchronized: yes|NTP service: active" >/dev/null 2>&1; then
        info_status "16" "Checking clock synchronization" "ok" "system clock synchronized"
    else
        info_status "16" "Checking clock synchronization" "warn" "clock not marked as synchronized"
    fi
elif [[ -f /.dockerenv ]]; then
    info_status "16" "Checking clock synchronization" "ok" "managed by host container engine"
else
    remote_date=$(curl -sI --max-time 3 https://github.com 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- || true)
    if [[ -n "$remote_date" ]]; then
        remote_sec=$(date -d "$remote_date" +%s 2>/dev/null || echo 0)
        local_sec=$(date +%s)
        diff_sec=$(( local_sec > remote_sec ? local_sec - remote_sec : remote_sec - local_sec ))
        if (( diff_sec < 15 )); then
            info_status "16" "Checking clock synchronization" "ok" "clock aligned (drift: ${diff_sec}s)"
        else
            info_status "16" "Checking clock synchronization" "warn" "clock drift detected (${diff_sec}s skew)"
        fi
    else
        info_status "16" "Checking clock synchronization" "warn" "unable to verify time status"
    fi
fi

# Check 17: Systemd / init system
if [[ -f /.dockerenv ]]; then
    info_status "17" "Checking systemd init system" "ok" "running inside Docker container (PID 1: $(ps -p 1 -o comm= 2>/dev/null || echo 'docker-init'))"
elif [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]] || [[ -d /run/systemd/system ]]; then
    systemd_version=$(systemctl --version 2>/dev/null | head -n1 || echo "systemd active")
    info_status "17" "Checking systemd init system" "ok" "$systemd_version"
else
    info_status "17" "Checking systemd init system" "warn" "systemd is not running as PID 1 (run 'wsl --shutdown' in PowerShell if recently enabled)"
fi


# ==========================================
# 2. Local Port Availability & Conflicts
# ==========================================

# Check 18, 19, 20: Critical ports (5432, 7350, 7349)
port_check_idx=18
for port_info in "5432:PostgreSQL" "7350:Nakama Client" "7349:Nakama gRPC"; do
    IFS=':' read -r port name <<< "$port_info"
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        info_status "$port_check_idx" "Checking port $port ($name)" "ok" "port in use (active container or local service)"
    else
        info_status "$port_check_idx" "Checking port $port ($name)" "ok" "port free"
    fi
    port_check_idx=$((port_check_idx + 1))
done

# Check 21: Local Firewall (UFW)
if command -v ufw >/dev/null 2>&1; then
    if sudo -n ufw status >/dev/null 2>&1; then
        ufw_status=$(sudo -n ufw status | grep "Status" | awk '{print $2}')
        if [[ "${ufw_status,,}" == "active" ]]; then
             info_status "21" "Checking local Firewall (UFW)" "warn" "UFW is ACTIVE. Ensure UDP port 7350 is explicitly allowed for multiplayer"
        else
             info_status "21" "Checking local Firewall (UFW)" "ok" "UFW is inactive (no blocking rules)"
        fi
    else
        info_status "21" "Checking local Firewall (UFW)" "ok" "installed but requires sudo to check status (assuming OK)"
    fi
else
    info_status "21" "Checking local Firewall (UFW)" "ok" "not installed"
fi


# ==========================================
# 3. Languages & Tools
# ==========================================

# Check 22: CMake
if ! command -v cmake >/dev/null 2>&1; then
    info_status "22" "Checking CMake" "warn" "not found in PATH"
else
    cmake_version=$(cmake --version | head -n1)
    info_status "22" "Checking CMake" "ok" "$cmake_version"
fi

# Check 23: Clang
if ! command -v clang >/dev/null 2>&1; then
    info_status "23" "Checking Clang" "warn" "not found in PATH"
else
    clang_version=$(clang --version | head -n1)
    info_status "23" "Checking Clang" "ok" "$clang_version"
fi

# Check 24: G++
if ! command -v g++ >/dev/null 2>&1; then
    info_status "24" "Checking G++" "warn" "not found in PATH"
else
    gxx_version=$(g++ --version | head -n1)
    info_status "24" "Checking G++" "ok" "$gxx_version"
fi

# Check 25: .NET SDK version against global.json
if ! command -v dotnet >/dev/null 2>&1; then
    info_status "25" "Checking .NET SDK" "error" "CLI not found"
    fail=1
else
    dotnet_version=$(dotnet --version)
    if [[ -f global.json ]]; then
        expected_version=$(jq -r '.sdk.version // empty' global.json 2>/dev/null || true)
        if [[ -n "$expected_version" ]]; then
            if [[ "$dotnet_version" != "$expected_version"* ]]; then
                info_status "25" "Checking .NET SDK" "warn" "expected $expected_version, got $dotnet_version"
            else
                info_status "25" "Checking .NET SDK" "ok" "version $dotnet_version"
            fi
        else
            info_status "25" "Checking .NET SDK" "ok" "version $dotnet_version (no global.json version constraint)"
        fi
    else
        info_status "25" "Checking .NET SDK" "ok" "version $dotnet_version (global.json not found)"
    fi
fi

# Check 26: Installed .NET Runtimes
if ! command -v dotnet >/dev/null 2>&1; then
    info_status "26" "Checking .NET Runtimes" "error" "dotnet CLI not found"
    fail=1
else
    runtimes_list=$(dotnet --list-runtimes 2>/dev/null || true)
    if [[ -n "$runtimes_list" ]]; then
        runtime_summary=$(echo "$runtimes_list" | awk '{print $1 " " $2}' | paste -sd, -)
        info_status "26" "Checking .NET Runtimes" "ok" "$runtime_summary"
        log "Installed runtimes:\n$runtimes_list"
    else
        info_status "26" "Checking .NET Runtimes" "warn" "no runtimes found via dotnet --list-runtimes"
    fi
fi

# Check 27: Go
if ! command -v go >/dev/null 2>&1; then
    info_status "27" "Checking Go" "error" "not found"
    fail=1
else
    go_version=$(go version)
    info_status "27" "Checking Go" "ok" "$go_version"
fi

# Check 28: Godot editor
if ! command -v godot >/dev/null 2>&1; then
    info_status "28" "Checking Godot editor" "error" "not found in PATH"
    fail=1
else
    godot_version=$(godot --version | head -n1)
    info_status "28" "Checking Godot editor" "ok" "$godot_version"
fi

# Check 29: Godot Vulkan rendering
if command -v godot >/dev/null 2>&1; then
    if godot --rendering-driver vulkan --headless --editor --quit >/dev/null 2>&1; then
        info_status "29" "Checking Godot Vulkan rendering" "ok" "headless Vulkan initialization succeeded"
    else
        info_status "29" "Checking Godot Vulkan rendering" "warn" "failed to initialize Vulkan renderer in headless mode"
    fi
else
    info_status "29" "Checking Godot Vulkan rendering" "warn" "skipped (Godot binary not found)"
fi

# Check 30: Aseprite
if ! command -v aseprite >/dev/null 2>&1; then
    info_status "30" "Checking Aseprite" "error" "not found in PATH"
    fail=1
else
    aseprite_version=$(aseprite --version | head -n1)
    info_status "30" "Checking Aseprite" "ok" "$aseprite_version"
fi

# Check 31: Git
if ! command -v git >/dev/null 2>&1; then
    info_status "31" "Checking Git" "error" "not found in PATH"
    fail=1
else
    git_version=$(git --version | head -n1)
    info_status "31" "Checking Git" "ok" "$git_version"
fi

# Check 32: Git repository status
if command -v git >/dev/null 2>&1; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git branch --show-current 2>/dev/null)
        if [[ -z "$git_branch" ]]; then
            git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
        fi
        git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        info_status "32" "Checking Git repository" "ok" "branch: $git_branch, commit: $git_hash"
    else
        info_status "32" "Checking Git repository" "warn" "current directory is not a git repository"
    fi
else
    info_status "32" "Checking Git repository" "warn" "git not found"
fi

# Check 33: Git LFS
if ! command -v git >/dev/null 2>&1 || ! git lfs version >/dev/null 2>&1; then
    info_status "33" "Checking Git LFS" "error" "not found"
    fail=1
else
    lfs_version=$(git lfs version | head -n1)
    if ! git lfs env | grep -q "Local"; then
        info_status "33" "Checking Git LFS" "warn" "may not be properly installed"
    else
        info_status "33" "Checking Git LFS" "ok" "$lfs_version"
    fi
fi

# Check 34: Git LFS integrity (pending binary downloads)
if command -v git >/dev/null 2>&1 && command -v git lfs >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git lfs ls-files 2>&1 | grep -q '^-'; then
        info_status "34" "Checking Git LFS integrity" "error" "missing binary files detected (run 'git lfs pull')"
        fail=1
    else
        info_status "34" "Checking Git LFS integrity" "ok" "all LFS files downloaded"
    fi
else
    info_status "34" "Checking Git LFS integrity" "ok" "skipped"
fi

# Check 35: GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    info_status "35" "Checking GitHub CLI" "error" "not found"
    fail=1
else
    gh_version=$(gh --version | head -n1)
    if ! gh auth status >/dev/null 2>&1; then
        info_status "35" "Checking GitHub CLI" "warn" "not authenticated - run 'gh auth login'"
    else
        info_status "35" "Checking GitHub CLI" "ok" "$gh_version"
    fi
fi


# ==========================================
# 4. Docker & Docker Compose
# ==========================================

# Check 36: Docker CLI
if ! command -v docker >/dev/null 2>&1; then
    info_status "36" "Checking Docker" "error" "not found in PATH"
    fail=1
else
    info_status "36" "Checking Docker" "ok" "CLI available"
fi

# Check 37: Docker daemon
if ! command -v docker >/dev/null 2>&1; then
    info_status "37" "Checking Docker daemon" "error" "skipped"
    fail=1
else
    if docker info >/dev/null 2>&1; then
        info_status "37" "Checking Docker daemon" "ok" "accessible"
    else
        info_status "37" "Checking Docker daemon" "error" "not accessible"
        fail=1
    fi
fi

# Check 38: Docker socket access inside container
if [[ -f /.dockerenv ]]; then
    if [[ -S /var/run/docker.sock ]] && docker ps >/dev/null 2>&1; then
        info_status "38" "Checking Docker socket access" "ok" "socket mounted and accessible"
    elif [[ -S /var/run/docker.sock ]]; then
        info_status "38" "Checking Docker socket access" "warn" "socket mounted but permission denied"
    else
        info_status "38" "Checking Docker socket access" "ok" "isolated container (no host socket mounted)"
    fi
else
    info_status "38" "Checking Docker socket access" "ok" "not in container (native host)"
fi

# Check 39: Docker Compose
if ! command -v docker compose >/dev/null 2>&1; then
    info_status "39" "Checking Docker Compose" "error" "plugin not found"
    fail=1
else
    info_status "39" "Checking Docker Compose" "ok" "$(docker compose version --short)"
fi


# ==========================================
# 5 & 6. Docker Compose Services & Backend Responding
# ==========================================

if [[ -f docker-compose.yml ]]; then
    # Check 40: Docker Compose services active overall
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -v '^$' || true)
    if [[ -n "$running_services" ]]; then
        info_status "40" "Checking Docker Compose services" "ok" "services active"
    else
        info_status "40" "Checking Docker Compose services" "warn" "no services running"
    fi

    # Check 41: Service 'postgres'
    if docker compose ps --format '{{.Service}}' --filter "status=running" 2>/dev/null | grep -q "^postgres$" || \
       docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^postgres$"; then
         info_status "41" "Checking service 'postgres'" "ok" "running"
    else
        if docker compose ps --services 2>/dev/null | grep -q "^postgres$"; then
            info_status "41" "Checking service 'postgres'" "warn" "defined but not running"
        else
            info_status "41" "Checking service 'postgres'" "warn" "not defined"
        fi
    fi

    # Check 42: Service 'nakama'
    if docker compose ps --format '{{.Service}}' --filter "status=running" 2>/dev/null | grep -q "^nakama$" || \
       docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^nakama$"; then
         info_status "42" "Checking service 'nakama'" "ok" "running"
    else
        if docker compose ps --services 2>/dev/null | grep -q "^nakama$"; then
            info_status "42" "Checking service 'nakama'" "warn" "defined but not running"
        else
            info_status "42" "Checking service 'nakama'" "warn" "not defined"
        fi
    fi

    # Check 43: PostgreSQL connectivity
    if docker compose exec -T postgres pg_isready -U postgres -d nakama >/dev/null 2>&1; then
        info_status "43" "Checking PostgreSQL connectivity" "ok" "accepting connections"
    else
        info_status "43" "Checking PostgreSQL connectivity" "warn" "not accepting connections"
    fi

    # Check 44: Nakama Client API (Port 7350)
    if curl -s -f http://nakama:7350/healthcheck >/dev/null 2>&1 || \
       curl -s -f http://localhost:7350/healthcheck >/dev/null 2>&1; then
        info_status "44" "Checking Nakama Client API (7350)" "ok" "responding"
    else
        info_status "44" "Checking Nakama Client API (7350)" "warn" "not responding"
    fi

    # Check 45: Nakama gRPC API (Port 7349)
    if curl -s --http2-prior-knowledge http://nakama:7349 >/dev/null 2>&1 || \
       nc -z nakama 7349 >/dev/null 2>&1 || \
       nc -z localhost 7349 >/dev/null 2>&1; then
        info_status "45" "Checking Nakama gRPC API (7349)" "ok" "responding"
    else
        info_status "45" "Checking Nakama gRPC API (7349)" "warn" "not responding"
    fi

    # Check 46: Nakama UDP API (Port 7350 - Realtime / Socket Routing)
    if command -v nc >/dev/null 2>&1; then
        if echo "" | nc -u -w 1 localhost 7350 >/dev/null 2>&1 || \
           echo "" | nc -u -w 1 nakama 7350 >/dev/null 2>&1; then
            info_status "46" "Checking Nakama UDP routing (7350)" "ok" "UDP socket reachable"
        else
            info_status "46" "Checking Nakama UDP routing (7350)" "warn" "UDP port 7350 unreachable (ensure 7350:7350/udp is declared in docker-compose.yml)"
        fi
    else
        info_status "46" "Checking Nakama UDP routing (7350)" "warn" "netcat (nc) not installed, skipping UDP test"
    fi
else
    info_status "40" "Checking Docker Compose services" "warn" "docker-compose.yml not found"
    info_status "41" "Checking service 'postgres'" "warn" "docker-compose.yml not found"
    info_status "42" "Checking service 'nakama'" "warn" "docker-compose.yml not found"
    info_status "43" "Checking PostgreSQL connectivity" "warn" "docker-compose.yml not found"
    info_status "44" "Checking Nakama Client API (7350)" "warn" "docker-compose.yml not found"
    info_status "45" "Checking Nakama gRPC API (7349)" "warn" "docker-compose.yml not found"
    info_status "46" "Checking Nakama UDP routing (7350)" "warn" "docker-compose.yml not found"
fi


# ==========================================
# 7. Workspace, Editors & Shell Utilities
# ==========================================

# Check 47: Workspace folder
if [[ -f GodotNakama.code-workspace ]]; then
    info_status "47" "Checking workspace" "ok" "GodotNakama.code-workspace found"
else
    info_status "47" "Checking workspace" "warn" "workspace file not found"
fi

# Check 48: VS Code
if ! command -v code >/dev/null 2>&1; then
    info_status "48" "Checking VS Code" "warn" "not found in PATH"
else
    code_version=$(code --version | head -n1)
    info_status "48" "Checking VS Code" "ok" "version $code_version"
fi

# Check 49: Nano
if ! command -v nano >/dev/null 2>&1; then
    info_status "49" "Checking nano" "warn" "not found in PATH"
else
    nano_version=$(nano --version | head -n1)
    info_status "49" "Checking nano" "ok" "$nano_version"
fi

# Check 50: Bash
if ! command -v bash >/dev/null 2>&1; then
    info_status "50" "Checking bash" "error" "not found in PATH"
    fail=1
else
    bash_version=$(bash --version | head -n1)
    info_status "50" "Checking bash" "ok" "$bash_version"
fi

# Check 51: Zsh
if ! command -v zsh >/dev/null 2>&1; then
    info_status "51" "Checking zsh" "warn" "not found in PATH"
else
    zsh_version=$(zsh --version)
    info_status "51" "Checking zsh" "ok" "$zsh_version"
fi

# Check 52: PowerShell
if command -v pwsh >/dev/null 2>&1; then
    pwsh_version=$(pwsh --version 2>/dev/null | head -n1 || echo "pwsh active")
    info_status "52" "Checking PowerShell" "ok" "$pwsh_version"
elif command -v powershell.exe >/dev/null 2>&1; then
    info_status "52" "Checking PowerShell" "ok" "powershell.exe available (Windows host)"
elif command -v powershell >/dev/null 2>&1; then
    ps_version=$(powershell --version 2>/dev/null | head -n1 || echo "powershell active")
    info_status "52" "Checking PowerShell" "ok" "$ps_version"
else
    info_status "52" "Checking PowerShell" "warn" "not found in PATH"
fi

# Check 53: Tmux
if ! command -v tmux >/dev/null 2>&1; then
    info_status "53" "Checking tmux" "error" "not found in PATH"
    fail=1
else
    tmux_version=$(tmux -V)
    info_status "53" "Checking tmux" "ok" "$tmux_version"
fi

# Check 54: Starship
if ! command -v starship >/dev/null 2>&1; then
    info_status "54" "Checking Starship" "error" "not found"
    fail=1
else
    starship_version=$(starship --version | head -n1)
    info_status "54" "Checking Starship" "ok" "$starship_version"
fi


# ==========================================
# 8. External Connectivity & Network Health Checks
# ==========================================

# Check 55: DNS resolution performance
if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
        info_status "55" "Checking DNS resolution" "ok" "resolving external hosts correctly"
    else
        info_status "55" "Checking DNS resolution" "error" "unable to resolve external hosts"
        fail=1
    fi
else
    info_status "55" "Checking DNS resolution" "warn" "getent command not found"
fi

# Check 56: Strict localhost resolution
if command -v getent >/dev/null 2>&1; then
    if getent ahosts localhost | grep -qE "^127\.|^::1"; then
        resolved_ips=$(getent ahosts localhost | awk '{print $1}' | sort -u | paste -sd, -)
        info_status "56" "Checking localhost resolution" "ok" "resolves to local loopback ($resolved_ips)"
    else
        info_status "56" "Checking localhost resolution" "error" "localhost does not resolve to 127.x.x.x or ::1 (check /etc/hosts)"
        fail=1
    fi
else
    info_status "56" "Checking localhost resolution" "warn" "getent command not found, skipping check"
fi

# Check 57: GitHub (Git Push/Pull & APIs)
if curl -s --max-time 5 https://github.com >/dev/null 2>&1; then
    info_status "57" "Checking GitHub reachability" "ok" "reachable"
else
    info_status "57" "Checking GitHub reachability" "warn" "unreachable (git push/pull might fail)"
fi

# Check 58: NuGet Package Feed (C# Package Restore)
if curl -s --max-time 5 https://api.nuget.org/v3/index.json >/dev/null 2>&1; then
    info_status "58" "Checking NuGet reachability" "ok" "reachable"
else
    info_status "58" "Checking NuGet reachability" "warn" "unreachable (dotnet restore might fail)"
fi

# Check 59: Docker Hub (Pulling images)
if curl -s --max-time 5 https://registry-1.docker.io/v2/ >/dev/null 2>&1; then
    info_status "59" "Checking Docker Hub reachability" "ok" "reachable"
else
    info_status "59" "Checking Docker Hub reachability" "warn" "unreachable (docker pull might fail)"
fi

# Check 60: Godot Engine (Assets & Asset Library)
if curl -s --max-time 5 https://godotengine.org >/dev/null 2>&1; then
    info_status "60" "Checking Godot Engine reachability" "ok" "reachable"
else
    info_status "60" "Checking Godot Engine reachability" "warn" "unreachable (asset library might fail)"
fi


# ==========================================
# Final summary
# ==========================================
if (( fail == 0 )); then
    echo -e "\n[doctor] ${GREEN}All checks passed successfully!${NC}"
else
    echo -e "\n[doctor] ${RED}One or more critical checks failed.${NC}"
fi

exit $fail