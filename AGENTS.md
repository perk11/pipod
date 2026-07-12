## What this project is

`pipod` is a thin wrapper that runs a coding agent — the [pi coding agent](https://github.com/earendil-works/pi),
[Claude Code](https://code.claude.com/), or [OpenAI Codex CLI](https://developers.openai.com/codex/cli) — inside an
isolated Docker container: one persistent container per workspace directory, per agent (selected with the `claude` or
`codex` subcommand). **This repo does not contain any agent's source.** Each agent is installed from npm (latest
version) into the image built from its own `Dockerfile` under `pi/`, `claude/`, or `codex/`. The only code here is the
`pipod` bash script and the three image definitions.

## Repository layout

| Path                                          | Role                                                                                                                                                       |
|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `pipod`                                       | Bash entrypoint: builds the selected image, manages the per-workspace container, bootstraps config, runs `pi`, `claude`, or `codex`. Parameterized by `$AGENT`. |
| `pi/Dockerfile`                               | Ubuntu-based image: Node 22 + `npm` (distro packages, not nodesource), `fd`, `ripgrep`, pi installed globally, a `ubuntu` user uid/gid-mapped to the host. |
| `claude/Dockerfile`                           | Same base/user setup, plus `git`; installs `@anthropic-ai/claude-code` globally. Used when invoked as `pipod claude`.                                      |
| `codex/Dockerfile`                            | Same base/user setup, plus `git` (no `fd`/`ripgrep` — Codex has built-in search); installs `@openai/codex` globally. Used when invoked as `pipod codex`.            |
| `README.md`                                   | User-facing docs.                                                                                                                                          |

> **All pipod state lives outside the repo**, at `~/.pi/pipod/` on the host (`$CONFIG_DIR` in the script). For pi it's
> mounted into the container as `/home/ubuntu/.pi`; its `agent/{models,auth,settings}.json` hold pi's models, API keys,
> and behavior, bootstrapped from the host's `~/.pi/agent/` on first run. For Claude Code the shared config lives under
> `$CONFIG_DIR/claude/` and is mounted at `/home/ubuntu/.claude` (via `CLAUDE_CONFIG_DIR`); `.credentials.json` (auth)
> and `settings.json` are bootstrapped from the host's `~/.claude/`. For Codex the shared config lives under
> `$CONFIG_DIR/codex/` and is mounted at `/home/ubuntu/.codex` (via `CODEX_HOME`); `auth.json` (auth) and `config.toml`
> are bootstrapped from the host's `~/.codex/`. Codex also writes mutable SQLite state DBs into `CODEX_HOME` by default,
> which corrupts under concurrent projects, so `CODEX_SQLITE_HOME` relocates them to a per-workspace dir
> (`$CONFIG_DIR/workspaces/<ws>/codex-state/`). Per-workspace state for all agents lives under
> `~/.pi/pipod/workspaces/<ws>/` (`sessions/`, and optionally an `agent/` (pi), `claude/` (Claude), or `codex/` (Codex)
> override).

## How `pipod` works

Most logic is agent-agnostic; the per-agent differences are captured in a block that sets `$IMAGE_TAG`,
`$CONTAINER_PREFIX`, `$BUILD_DIR`, the mount source/dest pairs, `$AGENT_ENV_VAR`, the bootstrap file set, and
`$RUN_CMD`. Values below are for the default (`pi`) agent unless a `claude`- or `codex`-specific note is given.

- **Container name**: `pipod-<sanitized_workspace_path>` (or `pipod-claude-<sanitized_workspace_path>` for Claude
  Code, or `pipod-codex-<sanitized_workspace_path>` for Codex), with a `-nonet` suffix under `--no-network`, derived
  from the invocation directory (`WORKSPACE_DIR="$(pwd)"`). Network mode and agent are both encoded in the name, so
  each workspace has up to six independent containers (pi/claude/codex × net/nonet) that share workspace & config but
  keep their own installed packages; switching `-nn`, `claude`, or `codex` just uses the other container. `PROJECT_DIR`
  is where the `pipod` script lives.
- **Mounts** (set at `docker run`):
    - `$WORKSPACE_DIR` → `/workspace` (project files; also the work dir)
    - pi: `$CONFIG_DIR` (`$HOME/.pi/pipod`) → `/home/ubuntu/.pi` (shared config). Claude: `$CONFIG_DIR/claude` →
      `/home/ubuntu/.claude` (shared config: settings, CLAUDE.md, skills, agents, plugins, `.credentials.json`). Codex:
      `$CONFIG_DIR/codex` → `/home/ubuntu/.codex` (shared config: `config.toml`, `AGENTS.md`, rules, `auth.json`).
    - Per-workspace config override, only if the override dir exists: pi `$CONFIG_DIR/workspaces/<ws>/agent` →
      `/home/ubuntu/.pi/agent`; Claude `$CONFIG_DIR/workspaces/<ws>/claude` → `/home/ubuntu/.claude`; Codex
      `$CONFIG_DIR/workspaces/<ws>/codex` → `/home/ubuntu/.codex`.
    - `$CONFIG_DIR/workspaces/<ws>/sessions` → per-workspace sessions: pi `/home/ubuntu/.pi/agent/sessions`; Claude
      `/home/ubuntu/.claude/projects` (Claude's per-project transcripts & auto memory, isolated per workspace); Codex
      `/home/ubuntu/.codex/sessions` (Codex's per-project session transcripts, isolated per workspace).
    - Codex only: `$CONFIG_DIR/workspaces/<ws>/codex-state` → `/home/ubuntu/.codex/state` (per-workspace SQLite state
      DBs — `state_5.sqlite`, `logs_2/goals_1/memories_1.sqlite` — relocated out of the shared `CODEX_HOME` via
      `CODEX_SQLITE_HOME` so concurrent projects can't corrupt the WAL state).
- **Env**: pi `PI_CODING_AGENT_DIR=/home/ubuntu/.pi/agent`; Claude `CLAUDE_CONFIG_DIR=/home/ubuntu/.claude`; Codex
  `CODEX_HOME=/home/ubuntu/.codex`; Codex also sets `CODEX_SQLITE_HOME=/home/ubuntu/.codex/state`. Note Claude Code's
  `~/.claude.json` (app state/per-project trust) is **not** relocatable via `CLAUDE_CONFIG_DIR` and is left in-container;
  auth persists through the shared `.credentials.json` under the mounted config dir. Codex's `CODEX_HOME` relocates
  everything (config, auth, sessions, state DBs); `CODEX_SQLITE_HOME` overrides just the SQLite state DB location to a
  per-workspace dir so concurrent projects can't corrupt the WAL state.
- **User**: runs as `ubuntu`, uid/gid remapped to the host user via `--build-arg HOST_UID`/`HOST_GID`, so files written
  in the container are owned by the host user.
- **Reuse vs recreate**: `./pipod` reuses an existing container for the workspace/agent (`docker start` + `docker
  exec`); `./pipod -r` force-recreates it. The image is rebuilt on every run (layer-cached, so cheap when unchanged).
- **Config bootstrap**: on run, missing essential files are copied from the host with `localhost`/`127.0.0.1`
  rewritten to `host.docker.internal`. pi: `models.json`/`auth.json` from `~/.pi/agent/`. Claude: `.credentials.json`
  (auth)/`settings.json` from `~/.claude/`. Codex: `auth.json` (auth)/`config.toml` from `~/.codex/`. The same bootstrap
  also applies inside the per-workspace override dir if it exists.

## Directory ownership

Docker creates bind-mount sources as `root` when the host path doesn't exist at `docker run`/`docker start` time. A
root-owned directory is unwritable by the in-container `ubuntu` user and causes `EACCES: permission denied`. This bites
in two scenarios: first container creation, **and** reusing an existing container after a config tree was deleted —
Docker then recreates the missing bind sources as root on `docker start`, and the (previously create-only) ownership fix
never ran.

`pipod` therefore runs `prepare_config` on **every** invocation, before both `docker run` and `docker start`. It first
`chown`s any root-owned subtree under `~/.pi/pipod` back to the invoking user (`recover_root_owned` scans the config root
and `chown -R`s each root-owned entry it finds — covering both ancestors that would block `mkdir -p` and stale descendants
from older mount layouts — via `sudo -n` if available, else exits with the exact command to run), then `mkdir -p`s the
shared config dir (`~/.pi/pipod/agent` for pi, `~/.pi/pipod/claude` for Claude, `~/.pi/pipod/codex` for Codex) and the
per-workspace `~/.pi/pipod/workspaces/<ws>/sessions` dir (plus `~/.pi/pipod/workspaces/<ws>/codex-state` for Codex's
SQLite state), and bootstraps the agent's essential config (`models.json`/`auth.json` for pi;
`.credentials.json`/`settings.json` for Claude; `auth.json`/`config.toml` for Codex) from the host if missing.

## Commands

```bash
./pipod             # build pi image, reuse or create container, run pi
./pipod -r          # force recreate the pi container (image rebuilt from cache)
./pipod claude      # use the Claude Code image/container instead, run claude
./pipod claude -r   # force recreate the Claude container
./pipod codex       # use the Codex image/container instead, run codex
./pipod codex -r    # force recreate the Codex container
./pipod bash        # shell inside the pi container (add `claude` or `codex` for the others)
```

## Conventions & guardrails

- **All state is host-side**: both the shared config and the per-workspace `workspaces/` state live at
  `~/.pi/pipod/` (outside the repo, never baked into the image; runtime bind-mounts). Don't rely on any of it being
  baked into the image.
- **Don't break UID/GID mapping**: the `--build-arg HOST_UID`/`HOST_GID` + `USER ubuntu` setup is what makes host-owned
  files writable in the container. Preserve it.
- **This repo wraps agents, it doesn't fork them**: behavior changes to pi, Claude Code, or Codex itself belong
  upstream, or in their own config/extensions — not as patches here. Each agent's own environment variables and
  config-file locations (e.g. `CLAUDE_CONFIG_DIR`, `.credentials.json`, `CODEX_HOME`, `auth.json`) are relied upon,
  not reimplemented.
