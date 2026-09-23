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
# 2. Languages & Tools
# ==========================================

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
# 3. Docker & Docker Compose
# ==========================================

# Check Docker
if ! command -v docker >/dev/null 2>&1; then
    info_status "Checking Docker" "error" "not found in PATH"
    fail=1
else
    if docker info >/dev/null 2>&1; then
        info_status "Checking Docker" "ok" "daemon accessible"
    else
        info_status "Checking Docker" "error" "daemon not accessible"
        fail=1
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
# 4 & 5. Docker Compose Services & Backend Responding
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
# 6. Workspace, tmux, zsh, starship
# ==========================================

# Check workspace folder
if [[ -f GodotNakama.code-workspace ]]; then
    info_status "Checking workspace" "ok" "GodotNakama.code-workspace found"
else
    info_status "Checking workspace" "warn" "workspace file not found"
fi

# Check tmux
if ! command -v tmux >/dev/null 2>&1; then
    info_status "Checking tmux" "error" "not found in PATH"
    fail=1
else
    tmux_version=$(tmux -V)
    info_status "Checking tmux" "ok" "$tmux_version"
fi

# Check zsh
if ! command -v zsh >/dev/null 2>&1; then
    info_status "Checking zsh" "warn" "not found in PATH"
else
    zsh_version=$(zsh --version)
    info_status "Checking zsh" "ok" "$zsh_version"
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
# 7. External Connectivity Health Checks
# ==========================================

# GitHub (Git Push/Pull & APIs)
if curl -s --max-time 5 https://github.com >/dev/null 2>&1; then
    info_status "Checking GitHub reachability" "ok" "reachable"
else
    info_status "Checking GitHub reachability" "warn" "unreachable (git push/pull might fail)"
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