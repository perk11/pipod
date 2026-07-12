# pipod - Dockerized Coding Agents

<p align="center">
<img src="./logo.webp" width="194" alt="pipod Logo">
</p>

A Docker-based environment for running a coding agent — the
[pi coding agent](https://github.com/earendil-works/pi),
[Claude Code](https://code.claude.com/), or [OpenAI Codex CLI](https://developers.openai.com/codex/cli) — inside a
persistent Docker container, one container per directory (per agent). The current directory is automatically mounted
as `/workspace`. Internet access can optionally be turned off
(except for reaching `host.docker.internal`, which lets local models/gateways keep working).

This isolates the agent from the host system, which makes the execution of custom code or shell commands significantly
safer.

While not completely bulletproof (the agent can still delete or edit unexpected files within the mounted directory, or
attempt a container escape), this approach is vastly more secure than sandbox methods that rely on allowing or
disallowing specific shell commands.

## Quick Start

1. Ensure you have Docker installed.
2. Clone this repository.
3. Add alias to your `~/.bashrc` or `~/.zshrc` file:
    ```bash
    alias pipod='/path/to/the/repo/pipod'
    ```
   If you copy or symlink the script, keep the `pi/`, `claude/`, and `codex/` subdirectories next to it — each holds
   that agent's `Dockerfile`, which the script builds from.
4. Restart your shell or open a new terminal window.
5. `cd` into a directory containing your project.
6. (Optional) Run
    ```bash
    pipod bash
    ```
   and install your project dependencies inside the container.
7. Launch pipod:

    ```bash
    pipod
    ```

## Running Claude Code

To run [Claude Code](https://code.claude.com/) instead of pi, pass the `claude` command. Everything else works the same:

```bash
pipod claude          # start a Claude Code session
pipod claude bash     # drop into a shell in the Claude container
pipod claude -nn      # isolated, host-only network
pipod claude -r       # force recreate the Claude container
```

Claude Code uses a **separate image** (`pipod-claude`) and **separate containers** (`pipod-claude-<slug>[-nonet]`),
so pi and Claude side by side keep their own installed packages. Authentication is bootstrapped from your host's
`~/.claude/.credentials.json` on first run (copied into the shared config tree), and persists across sessions;
log in interactively inside the container once if it isn't already set up.

## Running Codex CLI

To run the [OpenAI Codex CLI](https://developers.openai.com/codex/cli) instead of pi, pass the `codex` command.
Everything else works the same:

```bash
pipod codex          # start a Codex session
pipod codex bash     # drop into a shell in the Codex container
pipod codex -nn      # isolated, host-only network
pipod codex -r       # force recreate the Codex container
```

Codex uses a **separate image** (`pipod-codex`) and **separate containers** (`pipod-codex-<slug>[-nonet]`), so each
agent keeps its own installed packages. Codex relocates all of its state (config, auth, sessions, state DBs) via the
`CODEX_HOME` environment variable. The home (`config.toml`, `auth.json`, skills) is **shared** across containers.
Codex also writes mutable SQLite state DBs (`state_5.sqlite`, `logs_2/goals_1/memories_1.sqlite`) into the home by
default, and sharing those across projects corrupts the WAL state (it wedges startup with `SQLITE_CANTOPEN`), so pipod
sets `CODEX_SQLITE_HOME` to relocate them to a per-project dir (`~/.pi/pipod/workspaces/<ws>/codex-state/`).
`config.toml` and `auth.json` are bootstrapped from your host's `~/.codex/`; if you sign in with a ChatGPT account or an
API key, run `codex login` inside the container once if it isn't already set up.

## How It Works

Each workspace directory is assigned its own persistent Docker container, named `pipod-<slug>[-nonet]` for pi,
`pipod-claude-<slug>[-nonet]` for Claude Code, or `pipod-codex-<slug>[-nonet]` for Codex, where `<slug>` is derived
from the workspace's absolute path. The three agents use separate images and separate containers, so they don't share
installed packages. Starting another `pipod`
instance reuses the existing container for the requested agent/mode, so any installed packages persist between
sessions. The container is automatically stopped (but kept on disk for reuse) once every session exits.

Current directory is mounted at `/workspace`.

Configuration is mounted from `~/.pi/pipod/` and is shared across all containers. If this directory does not
exist, it will be bootstrapped from `~/.pi/agent/` during the first run.

Per-workspace state (sessions, and optionally config overrides) is stored under `~/.pi/pipod/workspaces/`, organized by
workspace path. Each workspace gets its own subdirectory containing a `sessions/` folder. If an `agent/` folder also
exists inside a workspace subdirectory, it is used instead of the shared `~/.pi/pipod/agent/`, allowing per-workspace
model, auth, skills, plugins or settings overrides.

To reference models running on `localhost`, use `host.docker.internal` as the host.

| Path inside container             | Source on host                          | Purpose                                                |
|-----------------------------------|-----------------------------------------|--------------------------------------------------------|
| `/workspace`                      | Current working directory               | Project files                                          |
| `/home/ubuntu/.pi`                | `~/.pi/pipod/`                          | Shared config                                          |
| `/home/ubuntu/.pi/agent`          | `~/.pi/pipod/workspaces/<ws>/agent/`    | Per-workspace config override (if `agent/` dir exists) |
| `/home/ubuntu/.pi/agent/sessions` | `~/.pi/pipod/workspaces/<ws>/sessions/` | Per-workspace sessions                                 |

For Claude Code (`pipod claude`), the equivalent layout uses `CLAUDE_CONFIG_DIR` to relocate all of Claude's config
(settings, skills, agents, plugins, and credentials) into the shared tree, while **session transcripts and memory are
isolated per project**:

| Path inside container               | Source on host                          | Purpose                                                        |
|-------------------------------------|-----------------------------------------|----------------------------------------------------------------|
| `/workspace`                        | Current working directory               | Project files                                                  |
| `/home/ubuntu/.claude`              | `~/.pi/pipod/claude/`                   | Shared config (settings.json, CLAUDE.md, skills, `.credentials.json` auth) |
| `/home/ubuntu/.claude`              | `~/.pi/pipod/workspaces/<ws>/claude/`   | Per-workspace config override (if `claude/` dir exists)        |
| `/home/ubuntu/.claude/projects`     | `~/.pi/pipod/workspaces/<ws>/sessions/` | Per-project session transcripts & auto memory                  |

> Claude Code's `~/.claude.json` (app state such as per-project trust/allowed-tool state) is not relocatable via
> `CLAUDE_CONFIG_DIR`, so it is intentionally left in-container; authentication persists through the shared
> `.credentials.json` under the mounted config directory.

For Codex (`pipod codex`), the `CODEX_HOME` config dir is **shared**, while the **SQLite state DBs and session
transcripts are isolated per project**:

| Path inside container               | Source on host                             | Purpose                                                        |
|-------------------------------------|--------------------------------------------|----------------------------------------------------------------|
| `/workspace`                        | Current working directory                  | Project files                                                  |
| `/home/ubuntu/.codex`               | `~/.pi/pipod/codex/`                       | Shared config (`config.toml`, `AGENTS.md`, rules, `auth.json` auth) |
| `/home/ubuntu/.codex/sessions`      | `~/.pi/pipod/workspaces/<ws>/sessions/`    | Per-project session transcripts                                |
| `/home/ubuntu/.codex/state`         | `~/.pi/pipod/workspaces/<ws>/codex-state/` | Per-project SQLite state DBs (`state_5.sqlite`, …), via `CODEX_SQLITE_HOME` |

> **Permissions:** The host UID/GID are mapped directly into the container so that file permissions match your local
> host user.


## CLI Arguments

| Flag                  | Description                                                                                            |
|-----------------------|--------------------------------------------------------------------------------------------------------|
| `claude`              | Run the Claude Code agent instead of pi (separate image & container). Can combine with the flags below.|
| `codex`               | Run the OpenAI Codex CLI agent instead of pi (separate image & container). Can combine with the flags below.|
| `-r`, `--recreate`    | Force recreate the container (image rebuilt from cache); discards anything installed inside it         |
| `--no-cache`          | Build the image without Docker cache (forces an agent upgrade)                                         |
| `-nn`, `--no-network` | Block internet access; only allow reaching the host (host.docker.internal). Uses a separate container. |
| `-h`, `--help`        | Show the help message                                                                                  |
| `bash`                | Open an interactive shell inside the container                                                         |

Flags can be combined, e.g. `pipod --no-cache -r -nn` rebuilds without cache and recreates the no-network container.

## Network Isolation (--no-network)

By default, a pipod container has full internet access. Pass `-nn` / `--no-network` to lock it down to host-only:

```bash
pipod -nn
```

This puts the container on an isolated Docker network (`pipod-no-net`) with no route to the internet, while pointing
`host.docker.internal` at that network's on-link bridge gateway so the host (and any models running on your host) stays
reachable. On startup pipod probes real connectivity and warns if the internet is still reachable or the host isn't
to confirm that nothing went wrong.

Because the two modes use separate containers (`pipod-<slug>-nonet` for `--no-network` alongside the normal
`pipod-<slug>`), switching between them is instant, but each container keeps its own installed packages.
`-r` only recreates the corresponding container.

## About the Docker Image

The Docker image is based on Ubuntu 26.04 (with a plan to stick to Ubuntu LTS releases) and is built automatically by
`./pipod` if it does not already exist. Passwordless sudo is enabled in the container to make dependency installation
simple.

I chose Ubuntu over Alpine to make it easier to run many different projects without compatibility surprises.

There are three images, each defined by its own `Dockerfile` in a subdirectory: `pi/Dockerfile` installs the
`@earendil-works/pi-coding-agent` npm package, `claude/Dockerfile` installs `@anthropic-ai/claude-code`, and
`codex/Dockerfile` installs `@openai/codex` (the latter two also install `git`, which their built-in commit/PR
workflows rely on). The script builds the right one based on whether you pass `claude` or `codex`.

`pi`/`claude`/`codex` are installed without version pinning, so the latest published version is fetched when an image is first
built. Later invocations reuse the Docker cache and won't pick up newer versions automatically. To upgrade an agent
and other dependencies, either run `pi update` / `claude update` / `codex update` inside a `pipod bash` (or
`pipod claude bash` / `pipod codex bash`) session, or rebuild the image from scratch with `-r`.  
Note that recreating a container discards any changes you made inside it.

```bash
./pipod --no-cache -r           # rebuild the pi image/container
./pipod claude --no-cache -r    # rebuild the Claude Code image/container
./pipod codex --no-cache -r     # rebuild the Codex image/container
```

I've only tested this on Linux; it may or may not work on macOS.

## Clean up

To clean up unused containers run `docker system prune`. You will lose any changes you made to the containers that are
not running at the moment this command runs.

## Limitations

* The agent cannot currently run another Docker container. It might be possible with privileged containers, but that
  brings its own set of security challenges.
* `--no-network` uses a separate container from the normal (Internet-enabled) one, so the two don't share installed
  packages - anything installed in one mode's container isn't visible in the other.
* The container name is derived from the absolute workspace path, slugified. A collision is possible if two
  directories slugify to the same value, e.g. `my-project` and `my_project`. If that happens, they will share a
  container.
* The agent can't follow symlinks that point outside of the current directory.

## Motivation

While isolating an environment in a Docker container is a simple task in principle, this project aims to provide an
easy-to-use interface and handle the edge cases (container reuse, automatic stopping, and getting permissions right).

Bash was chosen as the implementation language to avoid runtime dependencies, though I could see switching to something
like Go if there is significant future development.

## Vibe Coding

LLMs were heavily used to build this project, but everything was reviewed, understood, and carefully tested by a human.
This is not your run-of-the-mill AI slop.
