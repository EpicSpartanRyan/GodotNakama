# AGENTS.md — GodotNakama

How the local AI-assisted workflow in this repo is set up, so any agent
(or a fresh clone) can reproduce it. The goal: imagination → game with the
least friction possible.

## The environment

- VS Code runs in the devcontainer. **Cline** (`saoudrizwan.claude-dev`) is
  the coding agent; **Godot Tools** (`geequlim.godot-tools`) provides
  GDScript/C# debugging.
- Cline talks to a local model via Ollama:
  - Provider: Ollama — base URL `http://host.docker.internal:11434`
    (NOT `localhost` — inside the container, localhost is the container
    itself and gives ECONNREFUSED; requires "Expose Ollama to the network"
    on in the Ollama app).
  - Model: `qwen3-coder:30b-a3b-q4_K_M`, context window 65536.
  - Cline's config lives in `~/.cline`, mounted as a named volume — it
    survives devcontainer rebuilds.
- Node 22 is installed in the devcontainer.

## Agent skills (gamedev)

- 80 skills from `gamedev-skills/awesome-gamedev-agent-skills` are installed
  in `./.agents/skills/` (project scope). Let the skills router pick the
  2–3 relevant skills per task instead of guessing APIs.
- Only `skills-lock.json` is committed; `.agents/` is gitignored. On a fresh
  clone, restore the exact locked versions with:

  ```sh
  npx skills install
  ```

## Godot MCP (Cline ↔ Godot editor)

- The `godot-mcp` editor plugin (v1.12.18) is installed via
  `client/sample-game/plug.gd`
  (`plug("yanhuifair/godot-mcp", {"tag": "v1.12.18", "dev": true})`) with the
  "Godot: Install Addons" task, and enabled in Godot
  (Project → Project Settings → Plugins → Godot MCP). It is a dev-only
  editor plugin (AGPL-3.0) and does not affect the game's license.
- Godot (v4.7.2 mono) runs inside the devcontainer with its GUI via WSLg.
  The plugin listens on `127.0.0.1:9876` (loopback only) — the editor and
  the MCP server must run in the same container, or the live tools can't
  connect.
- Cline connects to it through its own `cline_mcp_settings.json`
  (Cline panel → MCP Servers → Installed → Configure MCP Servers):

  ```json
  {
    "mcpServers": {
      "godot-mcp": {
        "command": "npx",
        "args": ["-y", "@yanhuifair/godot-mcp", "-p", "/workspaces/GodotNakama/client/sample-game"],
        "disabled": false,
        "autoApprove": ["get_status", "search_tools", "list_scenes"]
      }
    }
  }
  ```

  `-p` must point at the folder containing `project.godot`
  (`client/sample-game`), not the repo root.
- **Cline does NOT read `.vscode/mcp.json`** — that file is for VS Code /
  GitHub Copilot only (it carries the same `godot-mcp` server entry).
- 386 tools. Use `search_tools` to find the right one and `get_status` to
  check the connection (it reports the project path and whether the editor
  is reachable). 220+ file tools (scenes, scripts, resources) work without
  Godot open; the live editor/runtime tools need the editor running.

## Docs (RAG) — pending

- Before writing Godot/Nakama code, run `mnem retrieve` against the
  `godotnakama-docs` graph (cloned `godotengine/godot-docs` +
  `heroiclabs/nakama-docs`, ingested with mnem). **Status: not built yet**
  (step 5 of the setup) — do not assume the graph exists; if
  `mnem retrieve` finds nothing, say so instead of guessing APIs.

## Testing

- Unit/input tests use GUT. Simulate input with `Input.action_press()` /
  `Input.parse_input_event()` in test scenes.
- Run headless: `godot --headless --quit-after N` and read stdout/stderr.
- Profiling: convert `.nettrace` files first —
  `dotnet-trace convert *.nettrace --format speedscope` — then read the
  JSON.
