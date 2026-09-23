#!/usr/bin/env bash
# doctor.sh - Diagnostic script for Godot Nakama development environment
#
# This script checks the health of the development environment:
# - Docker and Docker Compose availability
# - Running services (PostgreSQL, Nakama, Godot container)
# - .NET SDK version matches global.json
# - Godot editor availability
# - Aseprite availability
# - Git LFS and GitHub CLI availability
# - Basic connectivity to PostgreSQL and Nakama API
# - Display and GPU variables for graphical output
#
# Usage: ./doctor.sh [--verbose]
#
# Exit codes:
#   0 - All checks passed
#   1 - One or more critical checks failed
#   2 - Usage error

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

log() {
    if $VERBOSE; then
        echo "[doctor] $*"
    fi
}

info() {
    echo "[doctor] $*"
}

warn() {
    echo "[doctor] WARNING: $*" >&2
}

error() {
    echo "[doctor] ERROR: $*" >&2
}

fail=0

# Helper to run a command and capture output
run_cmd() {
    if $VERBOSE; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# 1. Check Docker
info "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
    error "Docker not found in PATH"
    fail=1
else
    # Use docker info to verify daemon is accessible; avoid template issues with newer Docker
    if docker info >/dev/null 2>&1; then
        log "Docker daemon is accessible"
    else
        error "Docker daemon not accessible"
        fail=1
    fi
fi

# 2. Check Docker Compose
info "Checking Docker Compose..."
if ! command -v docker compose >/dev/null 2>&1; then
    error "docker compose plugin not found"
    fail=1
else
    log "Docker Compose version: $(docker compose version --short)"
fi

# 3. Check .NET SDK version against global.json
info "Checking .NET SDK..."
if ! command -v dotnet >/dev/null 2>&1; then
    error ".NET CLI not found"
    fail=1
else
    dotnet_version=$(dotnet --version)
    log ".NET SDK version: $dotnet_version"
    # Read global.json if exists
    if [[ -f global.json ]]; then
        expected_version=$(jq -r '.sdk.version // empty' global.json 2>/dev/null || true)
        if [[ -n "$expected_version" ]]; then
            # Allow patch-only rollforward; compare leading components
            if [[ "$dotnet_version" != "$expected_version"* ]]; then
                warn ".NET SDK version mismatch: expected $expected_version, got $dotnet_version"
                # Not failing, just warning
            else
                log ".NET SDK version matches global.json"
            fi
        else
            warn "Could not read SDK version from global.json"
        fi
    else
        warn "global.json not found"
    fi
fi

# 4. Check Godot editor
info "Checking Godot editor..."
if ! command -v godot >/dev/null 2>&1; then
    error "Godot editor not found in PATH"
    fail=1
else
    godot_version=$(godot --version | head -n1)
    log "Godot version: $godot_version"
fi

# 5. Check Aseprite
info "Checking Aseprite..."
if ! command -v aseprite >/dev/null 2>&1; then
    error "Aseprite not found in PATH"
    fail=1
else
    aseprite_version=$(aseprite --version | head -n1)
    log "Aseprite version: $aseprite_version"
fi

# 6. Check Git LFS
info "Checking Git LFS..."
if ! command -v git lfs >/dev/null 2>&1; then
    error "Git LFS not found"
    fail=1
else
    lfs_version=$(git lfs version | head -n1)
    log "Git LFS version: $lfs_version"
    # Check if installed system-wide
    if ! git lfs env | grep -q "Local"; then
        warn "Git LFS may not be properly installed (check 'git lfs env')"
    fi
fi

# 7. Check GitHub CLI
info "Checking GitHub CLI..."
if ! command -v gh >/dev/null 2>&1; then
    error "GitHub CLI not found"
    fail=1
else
    gh_version=$(gh --version | head -n1)
    log "GitHub CLI version: $gh_version"
    # Check auth status (non-fatal)
    if ! gh auth status >/dev/null 2>&1; then
        warn "GitHub CLI not authenticated (run 'gh auth login')"
    fi
fi

# 8. Check Go (from devcontainer feature)
info "Checking Go..."
if ! command -v go >/dev/null 2>&1; then
    error "Go not found"
    fail=1
else
    go_version=$(go version)
    log "Go version: $go_version"
fi

# 9. Check Starship
info "Checking Starship..."
if ! command -v starship >/dev/null 2>&1; then
    error "Starship not found"
    fail=1
else
    starship_version=$(starship --version)
    log "Starship version: $starship_version"
fi

# 10. Check Docker Compose services (if compose file exists)
info "Checking Docker Compose services..."
if [[ -f docker-compose.yml ]]; then
    # Check if any services are running
    running_services=$(docker compose ps --services --filter "status=running" 2>/dev/null | grep -v '^$' || true)
    if [[ -n "$running_services" ]]; then
        log "Some services are running"
    else
        warn "No services appear to be running (try 'docker compose up -d')"
    fi

    # Check specific service health using robust format query
    for service in postgres nakama; do
        if docker compose ps --format '{{.Service}}' --filter "status=running" 2>/dev/null | grep -q "^${service}$" || \
           docker compose ps --services --filter "status=running" 2>/dev/null | grep -q "^${service}$"; then
            log "Service $service is running"
        else
            if docker compose ps --services 2>/dev/null | grep -q "^${service}$"; then
                warn "Service $service is defined but not running"
            else
                warn "Service $service not defined in docker-compose.yml"
            fi
        fi
    done

    # Quick connectivity checks
    info "Checking PostgreSQL connectivity..."
    if docker compose exec -T postgres pg_isready -U postgres -d nakama >/dev/null 2>&1; then
        log "PostgreSQL is accepting connections"
    else
        warn "PostgreSQL is not accepting connections"
    fi

    info "Checking Nakama APIs..."
    # Check Nakama Client/HTTP API (Port 7350)
    if curl -s -f http://nakama:7350/healthcheck >/dev/null 2>&1 || \
       curl -s -f http://localhost:7350/healthcheck >/dev/null 2>&1; then
        log "Nakama Client API (HTTP) is responding on port 7350"
    else
        warn "Nakama Client API not responding on port 7350"
    fi

    # Check Nakama gRPC API (Port 7349) using HTTP/2 prior knowledge or basic connection check
    if curl -s --http2-prior-knowledge http://nakama:7349 >/dev/null 2>&1 || \
       nc -z nakama 7349 >/dev/null 2>&1 || \
       nc -z localhost 7349 >/dev/null 2>&1; then
        log "Nakama gRPC API is responding on port 7349"
    else
        warn "Nakama gRPC API not responding on port 7349"
    fi
else
    warn "docker-compose.yml not found"
fi

# 11. Check display variables for GUI
info "Checking display variables..."
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
    warn "Neither DISPLAY nor WAYLAND_DISPLAY is set; GUI applications may not display"
else
    log "Display variables: DISPLAY=${DISPLAY:-unset}, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}"
fi

# 12. Check GPU device access (if NVIDIA)
info "Checking GPU access..."
if [[ -c /dev/dxg ]]; then
    log "/dev/dxg exists (WSLg DXG device)"
elif ls /dev/nvidia* >/dev/null 2>&1; then
    log "NVIDIA devices found"
else
    warn "No obvious NVIDIA device nodes found; GPU acceleration may not be available"
fi

# 13. Check workspace folder
info "Checking workspace..."
if [[ -f GodotNakama.code-workspace ]]; then
    log "Workspace file found: GodotNakama.code-workspace"
else
    warn "Workspace file not found"
fi

# Final summary
if (( fail == 0 )); then
    info "All checks passed"
else
    error "One or more checks failed (see above)"
fi

exit $fail