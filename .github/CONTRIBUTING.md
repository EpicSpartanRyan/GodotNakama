# Contributing

Contributions are welcome. You can open a pull request directly; an issue is
optional for small changes. For a substantial change, open an issue first to
discuss the approach before you invest time in implementation.

By submitting a contribution, you agree that it will be distributed under the
project's MIT License.

## Licensing and Dependencies Policy

Because this project serves as a foundational template for commercial projects, **we strictly do not accept pull requests that introduce dependencies with copyleft licenses** (e.g., GNU GPL, LGPL, AGPL). Any new libraries, tools, or code snippets introduced must operate under a permissive license (such as MIT, Apache 2.0, BSD-2-Clause, or Zlib) to ensure the project remains safe for closed-source and console development.

## Before you submit

- Keep changes focused and explain the problem they solve.
- Follow the style and structure of the surrounding code.
- Use a clear commit message with one of these prefixes: `feat:`, `fix:`,
  `docs:`, `test:`, `build:`, `ci:`, `refactor:`, or `chore:`.
- Do not commit credentials, generated build output, or other private data.
- Update documentation when behavior or setup instructions change.
- Describe the checks you ran and their results. You do not need to run every
  project check locally before opening a pull request; GitHub Actions provides
  CI checks for pull requests targeting `main`.
- CI should pass before a pull request is merged. A maintainer may make an
  exception for a known failure unrelated to the change; explain the failure
  and link relevant context in the pull request.

## Useful checks

Run the checks relevant to your change when practical:

```sh
dotnet build client/sample-game/Sample-Game.sln
dotnet test client/sample-game.Tests/Sample-Game.Tests.csproj
```

The Go backend tests can be run with:

```sh
cd backend
go test ./...
```

The RustFS storage integration test uses Testcontainers and requires Docker.
If you cannot run a check, mention that in your pull request rather than
reporting it as successful.

## Pull requests

Explain what changed and why, link a related issue if there is one, and include
relevant test or CI results. Review the pull request template before submitting.