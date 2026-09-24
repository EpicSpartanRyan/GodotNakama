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
    local message="$1"
    local status_type="$2" # ok, warn, error
    local detail="$3"

    case "$status_type" in
        ok)
            echo -e "[doctor] ${message}... ${GREEN}OK${NC}${detail:+ ($detail)}"
            ;;
        warn)
            echo -e "[doctor] ${message}... ${YELLOW}WARNING${NC}${detail:+ ($detail)}" >&2
            ;;
        error)
            echo -e "[doctor] ${message}... ${RED}ERROR${NC}${detail:+ ($detail)}" >&2
            ;;
    esac
}

fail=0

# ==========================================
# 1. Audio and Video Devices
# ==========================================

# Check display variables for GUI
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    info_status "Checking display variables" "warn" "neither DISPLAY nor WAYLAND_DISPLAY set"
else
    info_status "Checking display variables" "ok" "DISPLAY=${DISPLAY:-unset}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
fi

# Check GPU device access
if [[ -c /dev/dxg ]]; then
    info_status "Checking GPU access" "ok" "/dev/dxg exists (WSLg)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "Checking GPU access" "ok" "NVIDIA devices found"
else
    info_status "Checking GPU access" "warn" "no obvious GPU device nodes found"
fi

# Check NVIDIA drivers
if command -v nvidia-smi >/dev/null 2>&1; then
    gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n1 || echo "NVIDIA GPU")
    info_status "Checking NVIDIA drivers" "ok" "$gpu_name (nvidia-smi found)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    info_status "Checking NVIDIA drivers" "warn" "NVIDIA devices exist, but nvidia-smi is missing"
fi

# Check audio server (PulseAudio socket via WSLg)
pulse_socket="${PULSE_SERVER#unix:}"
if [[ -n "${PULSE_SERVER:-}" && -S "$pulse_socket" ]]; then
    info_status "Checking audio device" "ok" "PulseAudio socket active ($pulse_socket)"
elif [[ -n "${PULSE_SERVER:-}" ]]; then
    info_status "Checking audio device" "warn" "PULSE_SERVER set but socket not found at $pulse_socket"
else
    info_status "Checking audio device" "warn" "PULSE_SERVER environment variable not set"
fi


# ==========================================
# 1.1 Project Permissions, Disk Space, Filesystem & System Limits
# ==========================================

# Check write permissions recursively in current directory (ignoring .git internals)
if [[ -w "." ]]; then
    unwritable_items=$(find . -maxdepth 7 -not -path './.git*' ! -writable 2>/dev/null | head -n 5 || true)
    if [[ -n "$unwritable_items" ]]; then
        info_status "Checking project write permissions" "warn" "some files/folders are not writable (possible root ownership from docker)"
        log "Unwritable items found:\n$unwritable_items"
    else
        info_status "Checking project write permissions" "ok" "fully writable (recursive)"
    fi
else
    info_status "Checking project write permissions" "error" "current directory is not writable"
    fail=1
fi

# Check available disk space (warn if less than 5GB free on current partition)
if command -v df >/dev/null 2>&1; then
    free_space_kb=$(df -k . | awk 'NR==2 {print $4}')
    free_space_gb=$(( free_space_kb / 1024 / 1024 ))
    if (( free_space_gb < 5 )); then
        info_status "Checking available disk space" "warn" "low space: ${free_space_gb}GB remaining"
    else
        info_status "Checking available disk space" "ok" "${free_space_gb}GB available"
    fi
fi

# Check if project is inside Windows mount under WSL (/mnt/)
current_path="$(pwd)"
if [[ "$current_path" == /mnt/* ]]; then
    info_status "Checking project filesystem location" "warn" "located in Windows mount (/mnt/), performance may be degraded"
else
    info_status "Checking project filesystem location" "ok" "native Linux filesystem"
fi

# Check open file descriptors limit (nofile)
if command -v ulimit >/dev/null 2>&1; then
    nofile_limit=$(ulimit -n)
    if [[ "$nofile_limit" != "unlimited" ]] && (( nofile_limit < 4096 )); then
        info_status "Checking open file descriptors limit" "warn" "low limit ($nofile_limit), potential 'Too many open files' issues"
    else
        info_status "Checking open file descriptors limit" "ok" "limit is $nofile_limit"
    fi
fi

# Check total RAM allocation
if command -v free >/dev/null 2>&1; then
    ram_total_mb=$(free -m | awk '/^Mem:/ {print $2}')
    if (( ram_total_mb < 3800 )); then
        info_status "Checking total RAM" "warn" "low RAM allocated (${ram_total_mb}MB), builds may run out of memory"
    else
        info_status "Checking total RAM" "ok" "${ram_total_mb}MB allocated"
    fi
fi

# Check Swap memory availability
if command -v free >/dev/null 2>&1; then
    swap_total_kb=$(free -k | awk '/^Swap:/ {print $2}')
    if [[ -n "$swap_total_kb" ]] && (( swap_total_kb == 0 )); then
        info_status "Checking Swap memory" "warn" "no swap configured, risk of OOM kills under high load"
    else
        swap_total_mb=$(( swap_total_kb / 1024 ))
        info_status "Checking Swap memory" "ok" "${swap_total_mb}MB swap available"
    fi
fi

# Check system clock synchronization
if command -v timedatectl >/dev/null 2>&1 && timedatectl status >/dev/null 2>&1; then
    if timedatectl status | grep -E -i "synchronized: yes|NTP service: active" >/dev/null 2>&1; then
        info_status "Checking clock synchronization" "ok" "system clock synchronized"
    else
        info_status "Checking clock synchronization" "warn" "clock not marked as synchronized"
    fi
elif [[ -f /.dockerenv ]]; then
    info_status "Checking clock synchronization" "ok" "managed by host container engine"
else
    remote_date=$(curl -sI --max-time 3 https://github.com 2>/dev/null | grep -i "^date:" | cut -d' ' -f2- || true)
    if [[ -n "$remote_date" ]]; then
        remote_sec=$(date -d "$remote_date" +%s 2>/dev/null || echo 0)
        local_sec=$(date +%s)
        diff_sec=$(( local_sec > remote_sec ? local_sec - remote_sec : remote_sec - local_sec ))
        if (( diff_sec < 15 )); then
            info_status "Checking clock synchronization" "ok" "clock aligned (drift: ${diff_sec}s)"
        else
            info_status "Checking clock synchronization" "warn" "clock drift detected (${diff_sec}s skew)"
        fi
    else
        info_status "Checking clock synchronization" "warn" "unable to verify time status"
    fi
fi

# Check systemd / init system
if [[ -f /.dockerenv ]]; then
    info_status "Checking systemd init system" "ok" "running inside Docker container (PID 1: $(ps -p 1 -o comm= 2>/dev/null || echo 'docker-init'))"
elif [[ "$(ps -p 1 -o comm= 2>/dev/null)" == "systemd" ]] || [[ -d /run/systemd/system ]]; then
    systemd_version=$(systemctl --version 2>/dev/null | head -n1 || echo "systemd active")
    info_status "Checking systemd init system" "ok" "$systemd_version"
else
    info_status "Checking systemd init system" "warn" "systemd is not running as PID 1 (run 'wsl --shutdown' in PowerShell if recently enabled)"
fi


# ==========================================
# 2. Local Port Availability & Conflicts
# ==========================================

# Check critical ports (5432, 7350, 7349) for potential conflicts
for port_info in "5432:PostgreSQL" "7350:Nakama Client" "7349:Nakama gRPC"; do
    IFS=':' read -r port name <<< "$port_info"
    if ss -tln 2>/dev/null | grep -q ":$port "; then
        info_status "Checking port $port ($name)" "ok" "port in use (active container or local service)"
    else
        info_status "Checking port $port ($name)" "ok" "port free"
    fi
done


# ==========================================
# 3. Languages & Tools
# ==========================================

# Check C++ build tools (Clang, GCC, CMake)
if ! command -v cmake >/dev/null 2>&1; then
    info_status "Checking CMake" "warn" "not found in PATH"
else
    cmake_version=$(cmake --version | head -n1)
    info_status "Checking CMake" "ok" "$cmake_version"
fi

if ! command -v clang >/dev/null 2>&1; then
    info_status "Checking Clang" "warn" "not found in PATH"
else
    clang_version=$(clang --version | head -n1)
    info_status "Checking Clang" "ok" "$clang_version"
fi

if ! command -v g++ >/dev/null 2>&1; then
    info_status "Checking G++" "warn" "not found in PATH"
else
    gxx_version=$(g++ --version | head -n1)
    info_status "Checking G++" "ok" "$gxx_version"
fi

# Check .NET SDK version against global.json
if ! command -v dotnet >/dev/null 2>&1; then
    info_status "Checking .NET SDK" "error" "CLI not found"
    fail=1
else
    dotnet_version=$(dotnet --version)
    if [[ -f global.json ]]; then
        expected_version=$(jq -r '.sdk.version // empty' global.json 2>/dev/null || true)
        if [[ -n "$expected_version" ]]; then
            if [[ "$dotnet_version" != "$expected_version"* ]]; then
                info_status "Checking .NET SDK" "warn" "expected $expected_version, got $dotnet_version"
            else
                info_status "Checking .NET SDK" "ok" "version $dotnet_version"
            fi
        else
            info_status "Checking .NET SDK" "ok" "version $dotnet_version (no global.json version constraint)"
        fi
    else
        info_status "Checking .NET SDK" "ok" "version $dotnet_version (global.json not found)"
    fi

    # Check installed .NET Runtimes
    runtimes_list=$(dotnet --list-runtimes 2>/dev/null || true)
    if [[ -n "$runtimes_list" ]]; then
        runtime_summary=$(echo "$runtimes_list" | awk '{print $1 " " $2}' | paste -sd, -)
        info_status "Checking .NET Runtimes" "ok" "$runtime_summary"
        log "Installed runtimes:\n$runtimes_list"
    else
        info_status "Checking .NET Runtimes" "warn" "no runtimes found via dotnet --list-runtimes"
    fi
fi

# Check Go
if ! command -v go >/dev/null 2>&1; then
    info_status "Checking Go" "error" "not found"
    fail=1
else
    go_version=$(go version)
    info_status "Checking Go" "ok" "$go_version"
fi

# Check Godot editor
if ! command -v godot >/dev/null 2>&1; then
    info_status "Checking Godot editor" "error" "not found in PATH"
    fail=1
else
    godot_version=$(godot --version | head -n1)
    info_status "Checking Godot editor" "ok" "$godot_version"
fi

# Check Aseprite
if ! command -v aseprite >/dev/null 2>&1; then
    info_status "Checking Aseprite" "error" "not found in PATH"
    fail=1
else
    aseprite_version=$(aseprite --version | head -n1)
    info_status "Checking Aseprite" "ok" "$aseprite_version"
fi

# Check Git
if ! command -v git >/dev/null 2>&1; then
    info_status "Checking Git" "error" "not found in PATH"
    fail=1
else
    git_version=$(git --version | head -n1)
    info_status "Checking Git" "ok" "$git_version"
fi

# Check Git repository status
if command -v git >/dev/null 2>&1; then
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_branch=$(git branch --show-current 2>/dev/null)
        if [[ -z "$git_branch" ]]; then
            git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")
        fi
        git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
        info_status "Checking Git repository" "ok" "branch: $git_branch, commit: $git_hash"
    else
        info_status "Checking Git repository" "warn" "current directory is not a git repository"
    fi
fi

# Check Git LFS
if ! command -v git lfs >/dev/null 2>&1; then
    info_status "Checking Git LFS" "error" "not found"
    fail=1
else
    lfs_version=$(git lfs version | head -n1)
    if ! git lfs env | grep -q "Local"; then
        info_status "Checking Git LFS" "warn" "may not be properly installed"
    else
        info_status "Checking Git LFS" "ok" "$lfs_version"
    fi
fi

# Check for pending Git LFS downloads (pointers instead of real files)
if command -v git >/dev/null 2>&1 && command -v git lfs >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if git lfs ls-files 2>&1 | grep -q '^-'; then
        info_status "Checking Git LFS integrity" "error" "missing binary files detected (run 'git lfs pull')"
        fail=1
    else
        info_status "Checking Git LFS integrity" "ok" "all LFS files downloaded"
    fi
fi

# Check GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
    info_status "Checking GitHub CLI" "error" "not found"
    fail=1
else
    gh_version=$(gh --version | head -n1)
    if ! gh auth status >/dev/null 2>&1; then
        info_status "Checking GitHub CLI" "warn" "not authenticated - run 'gh auth login'"
    else
        info_status "Checking GitHub CLI" "ok" "$gh_version"
    fi
fi


# ==========================================
# 4. Docker & Docker Compose
# ==========================================

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    info_status "Checking Docker" "error" "not found in PATH"
    fail=1
else
    if docker info >/dev/null 2>&1; then
        info_status "Checking Docker daemon" "ok" "accessible"
    else
        info_status "Checking Docker daemon" "error" "not accessible"
        fail=1
    fi
fi

# Check Docker socket access inside container
if [[ -f /.dockerenv ]]; then
    if [[ -S /var/run/docker.sock ]] && docker ps >/dev/null 2>&1; then
        info_status "Checking Docker socket access" "ok" "socket mounted and accessible"
    elif [[ -S /var/run/docker.sock ]]; then
        info_status "Checking Docker socket access" "warn" "socket mounted but permission denied"
    else
        info_status "Checking Docker socket access" "ok" "isolated container (no host socket mounted)"
    fi
fi

# Check Docker Compose
if ! command -v docker compose >/dev/null 2>&1; then
    info_status "Checking Docker Compose" "error" "plugin not found"
    fail=1
else
    info_status "Checking Docker Compose" "ok" "$(docker compose version --short)"
fi


# ==========================================
# 5 & 6. Docker Compose Services & Backend Responding
# ==========================================

if [[ -f docker-compose.yml ]]; then
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -v '^$' || true)
    if [[ -n "$running_services" ]]; then
        info_status "Checking Docker Compose services" "ok" "services active"
    else
        info_status "Checking Docker Compose services" "warn" "no services running"
    fi

    for service in postgres nakama; do
        if docker compose ps --format '{{.Service}}' --filter "status=running" 2>/dev/null | grep -q "^${service}$" || \
           docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^${service}$"; then
             info_status "Checking service '$service'" "ok" "running"
        else
            if docker compose ps --services 2>/dev/null | grep -q "^${service}$"; then
                info_status "Checking service '$service'" "warn" "defined but not running"
            else
                info_status "Checking service '$service'" "warn" "not defined"
            fi
        fi
    done

    # PostgreSQL connectivity
    if docker compose exec -T postgres pg_isready -U postgres -d nakama >/dev/null 2>&1; then
        info_status "Checking PostgreSQL connectivity" "ok" "accepting connections"
    else
        info_status "Checking PostgreSQL connectivity" "warn" "not accepting connections"
    fi

    # Nakama Client API (Port 7350)
    if curl -s -f http://nakama:7350/healthcheck >/dev/null 2>&1 || \
       curl -s -f http://localhost:7350/healthcheck >/dev/null 2>&1; then
        info_status "Checking Nakama Client API (7350)" "ok" "responding"
    else
        info_status "Checking Nakama Client API (7350)" "warn" "not responding"
    fi

    # Nakama gRPC API (Port 7349)
    if curl -s --http2-prior-knowledge http://nakama:7349 >/dev/null 2>&1 || \
       nc -z nakama 7349 >/dev/null 2>&1 || \
       nc -z localhost 7349 >/dev/null 2>&1; then
        info_status "Checking Nakama gRPC API (7349)" "ok" "responding"
    else
        info_status "Checking Nakama gRPC API (7349)" "warn" "not responding"
    fi
else
    info_status "Checking Docker Compose config" "warn" "docker-compose.yml not found"
fi


# ==========================================
# 7. Workspace, Editors & Shell Utilities
# ==========================================

# Check workspace folder
if [[ -f GodotNakama.code-workspace ]]; then
    info_status "Checking workspace" "ok" "GodotNakama.code-workspace found"
else
    info_status "Checking workspace" "warn" "workspace file not found"
fi

# Check VS Code
if ! command -v code >/dev/null 2>&1; then
    info_status "Checking VS Code" "warn" "not found in PATH"
else
    code_version=$(code --version | head -n1)
    info_status "Checking VS Code" "ok" "version $code_version"
fi

# Check nano
if ! command -v nano >/dev/null 2>&1; then
    info_status "Checking nano" "warn" "not found in PATH"
else
    nano_version=$(nano --version | head -n1)
    info_status "Checking nano" "ok" "$nano_version"
fi

# Check bash
if ! command -v bash >/dev/null 2>&1; then
    info_status "Checking bash" "error" "not found in PATH"
    fail=1
else
    bash_version=$(bash --version | head -n1)
    info_status "Checking bash" "ok" "$bash_version"
fi

# Check zsh
if ! command -v zsh >/dev/null 2>&1; then
    info_status "Checking zsh" "warn" "not found in PATH"
else
    zsh_version=$(zsh --version)
    info_status "Checking zsh" "ok" "$zsh_version"
fi

# Check PowerShell (pwsh / powershell.exe / powershell)
if command -v pwsh >/dev/null 2>&1; then
    pwsh_version=$(pwsh --version 2>/dev/null | head -n1 || echo "pwsh active")
    info_status "Checking PowerShell" "ok" "$pwsh_version"
elif command -v powershell.exe >/dev/null 2>&1; then
    info_status "Checking PowerShell" "ok" "powershell.exe available (Windows host)"
elif command -v powershell >/dev/null 2>&1; then
    ps_version=$(powershell --version 2>/dev/null | head -n1 || echo "powershell active")
    info_status "Checking PowerShell" "ok" "$ps_version"
else
    info_status "Checking PowerShell" "warn" "not found in PATH"
fi

# Check tmux
if ! command -v tmux >/dev/null 2>&1; then
    info_status "Checking tmux" "error" "not found in PATH"
    fail=1
else
    tmux_version=$(tmux -V)
    info_status "Checking tmux" "ok" "$tmux_version"
fi

# Check Starship
if ! command -v starship >/dev/null 2>&1; then
    info_status "Checking Starship" "error" "not found"
    fail=1
else
    starship_version=$(starship --version | head -n1)
    info_status "Checking Starship" "ok" "$starship_version"
fi


# ==========================================
# 8. External Connectivity & Network Health Checks
# ==========================================

# Check DNS resolution performance
if command -v getent >/dev/null 2>&1; then
    if getent hosts github.com >/dev/null 2>&1; then
        info_status "Checking DNS resolution" "ok" "resolving external hosts correctly"
    else
        info_status "Checking DNS resolution" "error" "unable to resolve external hosts"
        fail=1
    fi
fi

# Check strict localhost resolution (critical for gRPC and Docker port binding)
if command -v getent >/dev/null 2>&1; then
    # ahosts checks all addresses (IPv4 and IPv6)
    if getent ahosts localhost | grep -qE "^127\.|^::1"; then
        resolved_ips=$(getent ahosts localhost | awk '{print $1}' | sort -u | paste -sd, -)
        info_status "Checking localhost resolution" "ok" "resolves to local loopback ($resolved_ips)"
    else
        info_status "Checking localhost resolution" "error" "localhost does not resolve to 127.x.x.x or ::1 (check /etc/hosts)"
        fail=1
    fi
else
    info_status "Checking localhost resolution" "warn" "getent command not found, skipping check"
fi

# GitHub (Git Push/Pull & APIs)
if curl -s --max-time 5 https://github.com >/dev/null 2>&1; then
    info_status "Checking GitHub reachability" "ok" "reachable"
else
    info_status "Checking GitHub reachability" "warn" "unreachable (git push/pull might fail)"
fi

# NuGet Package Feed (C# Package Restore)
if curl -s --max-time 5 https://api.nuget.org/v3/index.json >/dev/null 2>&1; then
    info_status "Checking NuGet reachability" "ok" "reachable"
else
    info_status "Checking NuGet reachability" "warn" "unreachable (dotnet restore might fail)"
fi

# Docker Hub (Pulling images)
if curl -s --max-time 5 https://registry-1.docker.io/v2/ >/dev/null 2>&1; then
    info_status "Checking Docker Hub reachability" "ok" "reachable"
else
    info_status "Checking Docker Hub reachability" "warn" "unreachable (docker pull might fail)"
fi

# Godot Engine (Assets & Asset Library)
if curl -s --max-time 5 https://godotengine.org >/dev/null 2>&1; then
    info_status "Checking Godot Engine reachability" "ok" "reachable"
else
    info_status "Checking Godot Engine reachability" "warn" "unreachable (asset library might fail)"
fi

# VS Code Marketplace (Extensions)
if curl -s --max-time 5 https://marketplace.visualstudio.com >/dev/null 2>&1; then
    info_status "Checking VS Code Marketplace reachability" "ok" "reachable"
else
    info_status "Checking VS Code Marketplace reachability" "warn" "unreachable (extensions sync might fail)"
fi

# Final summary
if (( fail == 0 )); then
    echo -e "\n[doctor] ${GREEN}All checks passed successfully!${NC}"
else
    echo -e "\n[doctor] ${RED}One or more critical checks failed.${NC}"
fi

exit $fail