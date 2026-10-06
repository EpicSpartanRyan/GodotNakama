# Godot Nakama Development Environment

A VS Code Dev Container for developing a Godot C# game with a Go/Nakama backend, PostgreSQL, RustFS, and art tools.

## Requirements

- Linux, or Ubuntu on WSL2 with WSLg for graphical applications.
- Docker Engine/Desktop with Compose and GPU support where applicable.
- VS Code with the Dev Containers extension.

The Linux and WSLg configurations are in `.devcontainer/linux-nvidia` and `.devcontainer/windows-wslg-nvidia`. Their display, GPU, and mount settings are host-specific.

## Start developing

1. Clone the repository and open `GodotNakama.code-workspace` in VS Code.
2. Choose **Dev Containers: Reopen in Container** and select the profile for your host.
3. Run **Tasks: Run Task → Templates: Instantiate** to create local config files from templates. Replace any placeholder values before using integrations that require credentials; do not commit secrets.

The workspace contains the game at `client/sample-game` and backend at `backend`. The Compose stack starts the `godot`, `postgres`, `rustfs`, and `nakama` services. Nakama waits for PostgreSQL and RustFS, then runs database migrations on startup.

To start or inspect the Linux stack manually from the repository root:

```bash
docker compose -f .devcontainer/linux-nvidia/docker-compose.yml up -d --build
docker compose -f .devcontainer/linux-nvidia/docker-compose.yml ps
docker compose -f .devcontainer/linux-nvidia/docker-compose.yml logs -f nakama
```

Use `.devcontainer/windows-wslg-nvidia/docker-compose.yml` instead on WSLg. Stop a stack with the same Compose file and `down`.

| Service | Port | Purpose |
| --- | ---: | --- |
| PostgreSQL | `5432` | Nakama database |
| Nakama | `7349`, `7350` TCP/UDP, `7351` | gRPC, realtime API, and console |
| RustFS | `9000` | S3-compatible object storage |
| Godot | `6007`, `6008` | Remote debugger and language server |

The local Compose files use development credentials. Do not reuse them outside a local environment.

## Build, run, and diagnose

Build the C# game from the repository root:

```bash
dotnet build client/sample-game/Sample-Game.sln
```

Start the editor with `godot -e --path client/sample-game`, or use **Godot: Start**. For common operations, use **Tasks: Run Task**:

- **Godot: Build**, **Godot: Export Game**, and **Godot: Install Addons**
- **Nakama: Go Vendor**, and **Nakama: Build & Restart**
- **Docker: View Logs (Nakama / DB)** and **Environment: Run Doctor**
- **Aseprite: Start** and **Inochi: Start**

`./doctor.sh` checks tools, hardware/display access, Docker, services, and network connectivity. Its hardware checks depend on the host and active display session.

## CI and deployment

GitHub Actions builds the Nakama Go plugin and exports the game for Windows, Linux, and macOS on pushes and pull requests to `main`. A separate workflow builds and publishes the development image to Docker Hub; deployment of Nakama is a manual workflow.

Artifacts from game and plugin builds are temporary CI artifacts, not signed releases. Local GitHub Actions can be run with the `Act:` tasks and `act`; workflows that use GitHub secrets or remote deployment still need suitable local configuration.

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

Dev Container feature versions and digests are recorded in each profile's lockfile. These pins improve consistency, but the environment is not fully bit-for-bit reproducible: some base images, OS packages, and downloads are not pinned by digest or checksum. RustFS currently uses the mutable `latest` tag.

## Troubleshooting

- **Container startup fails:** verify Docker/Compose, GPU support, and the host-specific display mounts for the selected profile.
- **Godot or an art tool cannot open a window:** check `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and the profile's display mounts.
- **Nakama is unavailable:** inspect `docker compose ... ps` and `logs -f nakama postgres rustfs` using the Compose file selected above.
- **Wrong .NET SDK:** run `dotnet --version`; `global.json` selects SDK `10.0.401`.
