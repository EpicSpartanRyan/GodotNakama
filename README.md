# Godot Nakama Development Environment

A VS Code Dev Container for developing a Godot C# game with a Go/Nakama backend, PostgreSQL, RustFS, and art tools.

## Requirements

- Linux, or Ubuntu on WSL2 with WSLg for graphical applications.
- Docker Engine/Desktop with Compose. NVIDIA Container Toolkit is needed only for the NVIDIA profile.
- VS Code with the Dev Containers extension.

Dev Container profiles are in `.devcontainer`: choose `linux-nvidia` or `windows-wslg-nvidia` for GPU acceleration, or `linux-cpu` or `windows-wslg-cpu` for software rendering without an NVIDIA runtime. The service stack and VS Code tooling are shared; host display mounts and renderer settings are composed from small profile-specific overlays.

## Start developing

1. Clone the repository and open `GodotNakama.code-workspace` in VS Code.
2. Choose **Dev Containers: Reopen in Container** and select the profile for your host and renderer.
3. Run **Tasks: Run Task → Templates: Instantiate** to create local config files from templates. Replace any placeholder values before using integrations that require credentials; do not commit secrets.

The workspace contains the game at `client/sample-game` and backend at `backend`. The Compose stack starts the `godot`, `postgres`, `rustfs`, and `nakama` services. Nakama waits for PostgreSQL and RustFS, then runs database migrations on startup.

To start or inspect the Linux NVIDIA stack manually from the repository root:

```bash
docker compose \
  -f .devcontainer/docker-compose.yml \
  -f .devcontainer/compose/linux.yml \
  -f .devcontainer/compose/linux-gpu.yml \
  up -d --build
docker compose \
  -f .devcontainer/docker-compose.yml \
  -f .devcontainer/compose/linux.yml \
  -f .devcontainer/compose/linux-gpu.yml \
  ps
```

For CPU-only Linux, use `.devcontainer/compose/cpu.yml` instead of `linux-gpu.yml`. On WSLg, use `wslg.yml` instead of `linux.yml`; add `wslg-gpu.yml` for GPU or `cpu.yml` for software rendering. Stop a stack with the same Compose file list and `down`.

| Service | Port | Purpose |
| --- | ---: | --- |
| PostgreSQL | `5432` | Nakama database |
| Nakama | `7349`, `7350` TCP/UDP, `7351` | gRPC, realtime API, and console |
| RustFS | `9000` | S3-compatible object storage |
| Godot | `6007`, `6008` | Remote debugger and language server |

The local Compose files use development credentials. Do not reuse them outside a local environment.

For a CPU-only profile, select `linux-cpu` or `windows-wslg-cpu` in the Dev Containers profile picker. These profiles set `LIBGL_ALWAYS_SOFTWARE=1` and do not request an NVIDIA runtime or mount `/dev/dxg`; rendering uses Mesa software rendering and may be slower. GPU profiles are `linux-nvidia` and `windows-wslg-nvidia`.

## Build, run, and diagnose

Build the C# game from the repository root:

```bash
dotnet build client/sample-game/Sample-Game.sln
```

Run the C# test project:

```bash
dotnet test client/sample-game.Tests/Sample-Game.Tests.csproj
```

The test project is included in the game solution, targets .NET 10, and uses xUnit v3. Its dependencies, including Testcontainers, are isolated from the exported game, which continues to target .NET 8. C# Dev Kit can discover and run tests from the VS Code Test Explorer.

Start the editor with `godot -e --path client/sample-game`, or use **Godot: Start**. For common operations, use **Tasks: Run Task**:

- **Godot: Build**, **Godot: Export Game**, **Godot: Install Addons**, and **.NET: Test**
- **Nakama: Go Vendor**, and **Nakama: Build & Restart**
- **Docker: View Logs (Nakama / DB)** and **Environment: Run Doctor**
- **Aseprite: Start** and **Inochi: Start**

`./doctor.sh` checks tools, hardware/display access, Docker, services, and network connectivity. Its hardware checks depend on the host and active display session.

## CI and deployment

GitHub Actions builds and tests the C# projects, builds the Nakama Go plugin, and exports the game for Windows, Linux, and macOS on pushes and pull requests to `main`. A separate workflow builds and publishes the development image to Docker Hub; deployment of Nakama is a manual workflow.

Artifacts from game and plugin builds are temporary CI artifacts, not signed releases. Local GitHub Actions can be run with the `Act:` tasks and `act`; workflows that use GitHub secrets or remote deployment still need suitable local configuration.

The Nakama backend's tests use Testify and run in CI. Run them locally with `cd backend && go test --mod=vendor ./...`, or use the **Nakama: Test** VS Code task. Docker must be available because the RustFS storage integration test starts a throwaway instance with Testcontainers.

## Pinned versions

Key versions currently configured:

| Component | Version |
| --- | --- |
| .NET SDK | `10.0.401` (`global.json`) |
| Godot .NET | `4.7.2` |
| Aseprite | `1.3.18.6` |
| Skia | `m124-08a5439a6b` |
| Inochi Creator | `0.8.6` |
| Nakama | `3.41.0` |
| NakamaClient | `3.22.1` |
| PostgreSQL | `18.6-trixie` |
| Go | `1.27.1` in CI; module declares `1.27.1` |

Dev Container feature versions and digests are recorded in each profile's lockfile, and the Dockerfile's direct APT packages are version-pinned. Renovate is configured to update those packages from Ubuntu 24.04 repositories; Dependabot does not update APT package pins in Dockerfiles. The environment is not fully bit-for-bit reproducible because base images, transitive OS packages, and downloaded artifacts are not all pinned by digest or checksum.

## Troubleshooting

- **Container startup fails:** verify Docker/Compose, GPU support, and the host-specific display mounts for the selected profile.
- **Godot or an art tool cannot open a window:** check `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and the profile's display mounts.
- **Nakama is unavailable:** inspect `docker compose ... ps` and `logs -f nakama postgres rustfs` using the Compose file selected above.
- **Wrong .NET SDK:** run `dotnet --version`; `global.json` selects SDK `10.0.401`.
