# Godot Nakama Development Environment

A containerized development environment for a Godot C# game with Nakama, PostgreSQL, Aseprite, and an integrated VS Code workflow.

The repository is designed to provide a repeatable development setup with Docker Compose, Dev Containers, Godot .NET, .NET 10, Go tooling, GitHub tooling, and local backend services ready to run together.

## Included Stack

- Godot 4.7.2 .NET edition for C# game development.
- .NET SDK 10 with the repository SDK version pinned through `global.json`.
- A pre-created C# solution in `client/sample-game`.
- `NakamaClient` included in the Godot C# project.
- Nakama server with automatic database migrations.
- PostgreSQL database initialized for Nakama.
- Aseprite built and installed inside the development image.
- Git LFS installed and initialized system-wide in the development image.
- GitHub CLI installed through a Dev Container Feature.
- Go installed through a Dev Container Feature.
- Starship installed and available for Bash.
- Docker outside of Docker configured for container-based tooling and Testcontainers.
- X11/WSLg display and audio environment variables configured for graphical tools.
- GPU-related Docker configuration for the Godot container.

## Repository Layout

```text
.
├── .devcontainer/
│   ├── devcontainer.json
│   └── devcontainer-lock.json
├── .github/
│   └── dependabot.yml
├── .vscode/
│   ├── launch.json
│   └── tasks.json
├── client/
│   ├── Dockerfile
│   └── sample-game/
│       ├── Sample-Game.csproj
│       ├── Sample-Game.sln
│       ├── project.godot
│       └── node_2d.tscn
├── nakama/
├── docker-compose.yml
├── global.json
└── GodotNakama.code-workspace
```

## Requirements

The intended host workflow uses Linux or WSL2 with Docker Desktop/ Docker Engine and VS Code.

Install or enable:

- Docker Engine or Docker Desktop with Compose support.
- VS Code.
- The Dev Containers extension for VS Code.
- WSLg when using graphical applications from WSL2.
- GPU drivers and Docker GPU support when using hardware acceleration.

The Compose configuration currently contains WSLg-specific mounts and GPU settings. The paths and device configuration may need adjustment for a different host setup.

## Open the Development Environment

1. Clone the repository and open it in VS Code.
2. Open `GodotNakama.code-workspace`.
3. Run **Dev Containers: Reopen in Container**.
4. Wait for the `godot` service and its dependent services to become ready.

The multi-root workspace opens both the repository root and `client/sample-game`, which keeps the project solution and its source tree available to the language tooling.

The Dev Container uses the `godot` Compose service as its main container. The workspace is mounted into `/home/ubuntu/GodotNakama`.

## Start the Services Manually

From the repository root:

```bash
docker compose up -d
```

Check service status:

```bash
docker compose ps
```

Follow Nakama logs:

```bash
docker compose logs -f nakama
```

Stop the development stack:

```bash
docker compose down
```

PostgreSQL and Nakama use healthchecks. Nakama runs its database migration before starting the server.

## Service Ports

| Service | Port | Purpose |
|---|---:|---|
| PostgreSQL | `5432` | Nakama database |
| Nakama API | `7349` | Client/API traffic |
| Nakama socket | `7350` | Realtime socket traffic |
| Nakama console | `7351` | Nakama web console |
| Godot remote debugger | `6007` | Remote debugging port exposed by the Dev Container configuration |
| Godot language server | `6008` | Language-server port exposed by the Dev Container configuration |

The database used by the local stack is named `nakama`. The default local PostgreSQL password in Compose is `localdb`.

## Build the C# Project

The repository contains a pre-created solution and project:

```text
client/sample-game/Sample-Game.sln
client/sample-game/Sample-Game.csproj
```

Build it from the repository root:

```bash
dotnet build client/sample-game/Sample-Game.sln
```

The SDK version is selected through `global.json`:

```bash
dotnet --version
```

The project uses:

- Godot.NET SDK `4.7.2`.
- Target framework `net8.0` for the regular project build.
- `NakamaClient` package version `3.22.0`.

## Run Godot

Godot is installed at `/usr/local/bin/godot` inside the development image.

From the project directory:

```bash
cd client/sample-game
godot -e
```

The VS Code task **Iniciar Godot** is also available from the Command Palette under **Tasks: Run Task**.

The project uses the `node_2d.tscn` scene as its main scene and is configured for Godot C# with GL Compatibility rendering.

## Debug C# with VS Code

The workspace includes two launch configurations in `.vscode/launch.json`.

### Play

**Play** builds the C# project first and launches Godot using `/usr/local/bin/godot`.

Use **Run and Debug** and select **Play**.

### Attach

**Attach** connects the debugger to a Godot process already running on `localhost:23685`.

Use this when Godot has already been started with a compatible C# debug configuration.

## VS Code Tasks

The preconfigured tasks include:

- **Install Starship in Bashrc**: adds the Starship initialization line only when it is not already present.
- **Start Godot**: starts the Godot editor.
- **Install Godot Addons**: installs Godot Addons specified in client/sample-game/plug.gd
- **Start Aseprite**: starts Aseprite.
- **Stop all Godot processes**: stops running Godot processes for the current environment.
- **Fix Godot game input**: disables embedded game mode in the local Godot 4.7 editor settings when needed.
- **build**: builds the C# project using the configured project directory.
- **Run Environment Doctor**: executes `./doctor.sh` to perform a complete diagnostic health check of the environment, services, audio, and external network connectivity.

Run them from **Tasks: Run Task** in VS Code.

## Aseprite

Aseprite is built from source during the Docker image build using the pinned Aseprite and Skia versions in `client/Dockerfile`.

Rebuild the development image after changing the Dockerfile:

```bash
docker compose build godot
docker compose up -d godot
```

Then start Aseprite with:

```bash
aseprite
```

Or use the **Iniciar Aseprite** VS Code task.

## Git LFS and GitHub CLI

Git LFS is installed in the Docker image and initialized system-wide:

```bash
git lfs version
git lfs env
```

GitHub CLI is provided by the Dev Container configuration:

```bash
gh --version
gh auth status
```

Authenticate with GitHub when required:

```bash
gh auth login
```

## Dev Container Features

The Dev Container includes:

- Docker outside of Docker.
- Go.
- Starship.
- GitHub CLI.

Resolved feature versions and integrity hashes are recorded in `.devcontainer/devcontainer-lock.json`.

Git LFS is intentionally installed in the Dockerfile rather than as a Dev Container Feature because this workspace uses a multi-root `.code-workspace` path as its configured `workspaceFolder`.

## Dependency Updates

Dependabot is configured in `.github/dependabot.yml` to monitor:

- Docker Compose dependencies.
- Docker image dependencies in `client`.
- NuGet dependencies in `client/sample-game`.

Updates are scheduled daily.

## Reproducibility Notes

The following versions are currently pinned in the repository:

- .NET SDK: `10.0.401` through `global.json`.
- Godot: `4.7.2`.
- Aseprite: `1.3.18.5`.
- Skia: `m124-08a5439a6b`.
- Nakama: `3.41.0`.
- NakamaClient: `3.22.0`.
- PostgreSQL: `18.6-trixie`.

The Dev Container feature lockfile also records resolved feature versions and integrity hashes.

## Troubleshooting

### The Dev Container fails before a feature command runs

Check that Docker can start the Compose services and that the host paths used for WSLg exist. The current configuration expects WSLg paths under the Ubuntu WSL distribution.

### Godot input does not work correctly in embedded mode

Run the **fix godot game input** task, then restart Godot.

### Godot or Aseprite cannot open a window

Check the `DISPLAY`, `WAYLAND_DISPLAY`, and `XDG_RUNTIME_DIR` variables, then verify the WSLg mounts in `docker-compose.yml`.

### Nakama is not ready

Inspect the service logs and health status:

```bash
docker compose ps
docker compose logs --tail=100 nakama
docker compose logs --tail=100 postgres
```

### The C# project cannot find the expected SDK

Run:

```bash
dotnet --info
dotnet --version
```

The installed SDK must satisfy the version selected by `global.json`.
