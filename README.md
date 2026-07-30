# pipod - Dockerized Coding Agents

<p align="center">
<img src="./logo.webp" width="194" alt="pipod Logo">
</p>

A Docker-based environment for running a coding agent — the
[pi coding agent](https://github.com/earendil-works/pi),
[Claude Code](https://code.claude.com/), [OpenAI Codex CLI](https://developers.openai.com/codex/cli), or
[JetBrains Junie CLI](https://junie.jetbrains.com/) — inside a
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
   If you copy or symlink the script, keep the `pi/`, `claude/`, `codex/`, and `junie/` subdirectories next to it — each holds
   that agent's `Dockerfile`, which the script builds from.
4. Restart your shell or open a new terminal window.
5. `cd` into a directory containing your project.
6. (Optional) Run
    ```bash
    pipod bash
    ```
   and install your project dependencies inside the container.
7. Launch pipod with `pi` coding agent:

    ```bash
    pipod
    ```

## How It Works

Each workspace directory is assigned its own persistent Docker container, named `pipod-<slug>[-nonet]` for pi,
`pipod-claude-<slug>[-nonet]` for Claude Code, `pipod-codex-<slug>[-nonet]` for Codex, or
`pipod-junie-<slug>[-nonet]` for Junie, where `<slug>` is derived from the workspace's absolute path. The four agents
use separate images and separate containers, so they don't share installed packages. Starting another `pipod`
instance reuses the existing container for the requested agent/mode, so any installed packages persist between
sessions. The container is automatically stopped (but kept on disk for reuse) once every session exits.

Current directory is mounted at `/workspace`.

Configuration is mounted from `~/.pipod/` and is shared across all containers. If this directory does not exist, it
will be bootstrapped from `~/.pi/agent/` during the first run. (On first run after upgrading from an older pipod, the
previous `~/.pi/pipod/` state is moved to `~/.pipod/` once.)

Per-workspace state is stored under `~/.pipod/workspaces/`, organized by workspace path **and split by agent** — each
workspace gets a `pi/`, `claude/`, `codex/`, and `junie/` subdirectory holding that agent's per-project data (sessions and other
session-scoped files, bind-mounted over the shared agent home so projects don't clobber each other) plus an optional
`config/` override. If a `config/` folder exists for an agent, it replaces the shared agent config for that workspace,
allowing per-workspace model, auth, skills, plugins or settings overrides.

To reference models running on `localhost`, use `host.docker.internal` as the host.

> **Permissions:** The host UID/GID are mapped directly into the container so that file permissions match your local
> host user.


## CLI Arguments

| Flag                  | Description                                                                                            |
|-----------------------|--------------------------------------------------------------------------------------------------------|
| `claude`              | Run the Claude Code agent instead of pi (separate image & container). Can combine with the flags below.|
| `codex`               | Run the OpenAI Codex CLI agent instead of pi (separate image & container). Can combine with the flags below.|
| `junie`               | Run the JetBrains Junie CLI agent instead of pi (separate image & container). Can combine with the flags below.|
| `-r`, `--recreate`    | Force recreate the container (image rebuilt from cache); discards anything installed inside it         |
| `--no-cache`          | Build the image without Docker cache (forces an agent upgrade)                                         |
| `-nn`, `--no-network` | Block internet access; only allow reaching the host (host.docker.internal). Uses a separate container. |
| `--no-tty`            | Allocate stdin (`-i`) but no pseudo-tty (`-t`); for piping input or running the agent non-interactively.|
| `-h`, `--help`        | Show the help message                                                                                  |
| `bash`                | Open an interactive shell inside the container                                                         |
| `stop`                | Stop the current workspace/agent container without removing it (it is reused next time). Honors the agent and `-nn`/`-r` selection, e.g. `pipod claude -nn stop`. |
| `update`              | Upgrade the agent inside the existing container via its own self-update (`pi update --self`, `claude update`, `codex update`, or `junie update`). pi/claude/codex are global npm installs under root-owned `/usr/local`, so they run as root (`sudo -H`); Junie updates its user-owned binary, so it needs no sudo. Doesn't rebuild the image or recreate the container, so packages installed inside are preserved, but updates won't carry over to other projects. Needs Internet, so it won't work with `--no-network`.|
| `--`                  | End of pipod's own options. Everything after `--` is forwarded verbatim to the agent (or to `bash` in shell mode). |

Flags can be combined, e.g. `pipod --no-cache -r -nn` rebuilds without cache and recreates the no-network container.

```bash
pipod stop                 # stop the pi container for this workspace
pipod claude stop          # stop the Claude container
pipod codex stop           # stop the Codex container
pipod junie stop           # stop the Junie container
pipod -nn stop             # stop the no-network container

pipod update               # upgrade pi inside its existing container
pipod claude update        # upgrade Claude Code inside its existing container
pipod codex update         # upgrade Codex CLI inside its existing container
pipod junie update         # upgrade Junie inside its existing container

# Pass arguments through to the agent
pipod -- --print "Summarize this codebase"      # runs `pi --print "..."`
pipod claude -- --permission-mode plan          # runs `claude --permission-mode plan`

# Non-interactive: pipe input without allocating a TTY
pipod --no-tty -- --print "What files are here?" < /dev/null
```

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

## About the Docker Images

The Docker images are separate for each agent and are all based on Ubuntu 26.04 (with a plan to stick to Ubuntu LTS releases). 
They are built automatically by `./pipod` if they do not already exist. Passwordless sudo is enabled in the container to make dependency installation
simple.

I chose Ubuntu over Alpine to make it easier to run many different projects without compatibility surprises.

`pi/Dockerfile` installs the `@earendil-works/pi-coding-agent` npm package, `claude/Dockerfile` installs `@anthropic-ai/claude-code`,
`codex/Dockerfile` installs `@openai/codex`, and `junie/Dockerfile` installs `@jetbrains/junie` The script builds the right one based on
whether you pass `claude`, `codex`, or `junie`. The images also all include `curl` and `git` and some agent-specific CLI tools.


## Running Claude Code/Codex/Junie

To run [Claude Code](https://code.claude.com/)/[OpenAI Codex CLI](https://developers.openai.com/codex/cli)/[JetBrains Junie CLI](https://junie.jetbrains.com/), pass the apropriate command. Everything else works the same:

```bash
pipod claude          # start a Claude Code session
pipod codex bash     # drop into a shell in the codex container
pipod junie -nn      # isolated, host-only network
```

## Agent-specific mounts
Claude Code's config (`CLAUDE_CONFIG_DIR`) is **shared** across containers while per-project session data is isolated
per workspace. Authentication (`.credentials.json`) is bootstrapped from your
host's `~/.claude/` on first run and persists across sessions; log in interactively inside the container once if it
isn't already set up.

| Path inside container             | Source on host                              | Purpose                                                |
|-----------------------------------|---------------------------------------------|--------------------------------------------------------|
| `/workspace`                      | Current working directory                   | Project files                                          |
| `/home/ubuntu/.pi`                | `~/.pipod/`                                 | Shared config                                          |
| `/home/ubuntu/.pi/agent`          | `~/.pipod/workspaces/<ws>/pi/config/`       | Per-workspace config override (if `config/` dir exists) |
| `/home/ubuntu/.pi/agent/sessions` | `~/.pipod/workspaces/<ws>/pi/sessions/`     | Per-workspace sessions                                 |

For Claude Code (`pipod claude`), `CLAUDE_CONFIG_DIR` relocates all of Claude's config (settings, skills, agents,
plugins, and credentials) into the shared tree, while the **per-project data Claude writes each session is isolated per
workspace** (the in-container cwd is always `/workspace`, so every workspace would otherwise map to the same Claude
project key and clobber each other):

| Path inside container                | Source on host                                   | Purpose                                                          |
|--------------------------------------|--------------------------------------------------|------------------------------------------------------------------|
| `/workspace`                         | Current working directory                        | Project files                                                    |
| `/home/ubuntu/.claude`               | `~/.pipod/claude/`                               | Shared config (settings.json, CLAUDE.md, skills, `.credentials.json` auth) |
| `/home/ubuntu/.claude`               | `~/.pipod/workspaces/<ws>/claude/config/`        | Per-workspace config override (replaces the shared config row above when present) |
| `/home/ubuntu/.claude/projects`      | `~/.pipod/workspaces/<ws>/claude/sessions/`      | Per-project session transcripts, memory, subagents, tool-results |
| `/home/ubuntu/.claude/file-history`  | `~/.pipod/workspaces/<ws>/claude/file-history/`  | Per-project file snapshots (checkpoint/rewind)                   |
| `/home/ubuntu/.claude/history.jsonl` | `~/.pipod/workspaces/<ws>/claude/history.jsonl`  | Per-project prompt history (up-arrow recall)                     |

> Claude Code's `~/.claude.json` (app state such as per-project trust/allowed-tool state) is not relocatable via
> `CLAUDE_CONFIG_DIR`, so it stays in `$HOME` inside the container; since containers are per-workspace, each workspace
> keeps its own. Authentication persists through the shared `.credentials.json` under the mounted config directory.

Codex's config (`CODEX_HOME`) is **shared** across containers while per-project data is isolated per workspace. 
Authentication (`auth.json`) is bootstrapped from your host's `~/.codex/` on first
run; run `codex login` inside the container once if it isn't already set up.

| Path inside container                | Source on host                                 | Purpose                                                          |
|--------------------------------------|------------------------------------------------|------------------------------------------------------------------|
| `/workspace`                         | Current working directory                      | Project files                                                    |
| `/home/ubuntu/.codex`                | `~/.pipod/codex/`                              | Shared config (`config.toml`, `AGENTS.md`, rules, `auth.json` auth) |
| `/home/ubuntu/.codex`                | `~/.pipod/workspaces/<ws>/codex/config/`       | Per-workspace config override (replaces the shared config row above when present) |
| `/home/ubuntu/.codex/sessions`       | `~/.pipod/workspaces/<ws>/codex/sessions/`     | Per-project session transcripts                                  |
| `/home/ubuntu/.codex/state`          | `~/.pipod/workspaces/<ws>/codex/state/`        | Per-project SQLite state DBs (`state_5.sqlite`, …), via `CODEX_SQLITE_HOME` |
| `/home/ubuntu/.codex/log`            | `~/.pipod/workspaces/<ws>/codex/log/`          | Per-project logs                                                 |
| `/home/ubuntu/.codex/history.jsonl`  | `~/.pipod/workspaces/<ws>/codex/history.jsonl` | Per-project prompt history                                       |

> Codex's mutable SQLite state DBs (`state_5.sqlite`, `logs_2/goals_1/memories_1.sqlite`) are relocated out of the
> shared `CODEX_HOME` via `CODEX_SQLITE_HOME`, because sharing them across projects would corrupt their WAL state and
> wedge startup with `SQLITE_CANTOPEN`.

Junie's config home is the fixed `~/.junie` directory (it has no config-dir environment variable to relocate it, so
pipod mounts the shared config there directly). It is **shared** across containers while per-project data is isolated
per workspace — see [How It Works](#how-it-works). On first run pipod bootstraps, from your host's `~/.junie/`:

- **Files:** `config.json` (base settings like `model`/`provider`/`flags`), `settings.json` (user/TUI settings, which
  Junie resolves at *higher* precedence than `config.json`), `allowlist.json` (the action allowlist), and
  `secure_credentials.json` (Junie's credential store — see auth below).
- **Directories:** `models/` (custom model profiles, which embed their own BYOK key/base URL — e.g. `models/glm.json`
  is used as `custom:glm`), `mcp/` (MCP servers), `skills/`, `commands/` (custom slash commands), and `agents/`
  (custom agents).

| Path inside container                          | Source on host                                          | Purpose                                                          |
|------------------------------------------------|--------------------------------------------------------|------------------------------------------------------------------|
| `/workspace`                                   | Current working directory                              | Project files                                                    |
| `/home/ubuntu/.junie`                          | `~/.pipod/junie/`                                      | Shared config (`config.json`, `settings.json`, `allowlist.json`, `secure_credentials.json`; `/account` keys live in the OS keyring — see above) |
| `/home/ubuntu/.junie`                          | `~/.pipod/workspaces/<ws>/junie/config/`               | Per-workspace config override (replaces the shared config row above when present) |
| `/home/ubuntu/.junie/cli-sessions/sessions`    | `~/.pipod/workspaces/<ws>/junie/sessions/`             | Per-project per-task transcripts (`events.jsonl`, `transcript.md`, `subagents/`) |
| `/home/ubuntu/.junie/logs`                     | `~/.pipod/workspaces/<ws>/junie/log/`                  | Per-project app + upgrade logs        



### Junie Authentication

Junie needs a JetBrains-Account credential, independent of your model profile (a `custom:` model's
own `apiKey` routes the LLM call but does **not** satisfy the gate). On your **host** this is usually already in place
with **no separate Junie login**: if you're signed into a JetBrains IDE or Toolbox, Junie reuses that sign-in.

That credential is stored in `~/.junie/secure_credentials.json`, which pipod bootstraps from your host on first run
and bind-mounts live thereafter — so **it carries across automatically**: sign in once on the host (directly, or via
the IDE/Toolbox) and every container is already authenticated, with no in-container login needed.

The exception is hosts where Junie keeps the credential in the **OS keyring** instead of the file (macOS Keychain,
Windows Credential Manager, or a Linux keyring Junie prefers): there's no file to copy, so the container starts
unauthenticated — then run `pipod junie` once and complete the login. Junie writes the result to the shared
`~/.junie/secure_credentials.json`, authenticating every later run, workspace container, and `pipod junie -r` recreation.

`pi`/`claude`/`codex` are installed without version pinning, so the latest published version is fetched when an image is first
built. `@jetbrains/junie` is likewise installed unpinned; its postinstall downloads the matching platform binary, and
the build then runs `junie update` once to pre-download the latest release (the npm package's pinned build otherwise
lags behind, so each container would re-download the full binary on first run). Later invocations reuse the Docker
cache and won't pick up newer versions automatically. To upgrade an agent
and other dependencies, either run the built-in `update` subcommand (the easiest path — it runs the agent's own
self-update inside the existing container without recreating it, so anything you installed there is preserved),
or rebuild the image from scratch with `-r`. Note that recreating a container discards any changes you made inside it.


```bash
./pipod update               # upgrade pi inside its existing container
./pipod claude update        # upgrade Claude Code inside its existing container
./pipod codex update         # upgrade Codex CLI inside its existing container
./pipod junie update         # upgrade Junie inside its existing container

./pipod --no-cache -r           # rebuild the pi image/container from scratch
./pipod claude --no-cache -r    # rebuild the Claude Code image/container
./pipod codex --no-cache -r     # rebuild the Codex image/container
./pipod junie --no-cache -r     # rebuild the Junie image/container
```

I've only tested this on Linux; it may or may not work on macOS.

## Clean up

To clean up unused containers run `docker system prune`. You will lose any changes you made to the containers that are
not running at the moment this command runs.

## Tests

The `pipod` script is covered by [bats-core](https://github.com/bats-core/bats-core) tests under `tests/`. They
exercise the argument parser (`parse_args`), per-agent setup (`select_agent`), the `--help` output, the `stop`
and `update` commands, and end-to-end `--` argument forwarding through a mocked `docker` binary. The `package.json` for the suite
lives under `tests/` too (not at the repo root) — it pins `bats` as a dev dependency so the tests are self-contained.

```bash
cd tests && npm install && npm test   # one-time install, then run every test
# or, from the repo root:
npm --prefix tests install
npm --prefix tests test
```

The mock-docker suites (`tests/stop.bats`, `tests/update.bats`, `tests/exec.bats`) do **not** require Docker to be installed — they shim
`docker` with `tests/docker-mock`. The unit tests under `tests/parse_args.bats` and `tests/select_agent.bats` source
`pipod` directly (a source-guard skips the main flow when sourced). Add new behavior to `pipod` by extracting it into
a small function next to `parse_args`/`select_agent` and adding a `.bats` file alongside the others.

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
