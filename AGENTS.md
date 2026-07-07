## What this project is

`pipod` is a thin wrapper that runs the [pi coding agent](https://github.com/earendil-works/pi) inside an isolated
Docker container — one persistent container per workspace directory. **This repo does not contain the pi agent source.**
Pi is installed from npm (latest version) into the image built from `Dockerfile`. The only code here is the `pipod` bash
script and the image definition.

## Repository layout

| Path                                          | Role                                                                                                                                                       |
|-----------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `pipod`                                       | Bash entrypoint: builds the image, manages the per-workspace container, bootstraps config, runs `pi`.                                                      |
| `Dockerfile`                                  | Ubuntu-based image: Node 22 + `npm` (distro packages, not nodesource), `fd`, `ripgrep`, pi installed globally, a `ubuntu` user uid/gid-mapped to the host. |
| `README.md`                                   | User-facing docs.                                                                                                                                          |

> **All pipod state lives outside the repo**, at `~/.pi/pipod/` on the host (`$CONFIG_DIR` in the script), mounted
> into every container as `/home/ubuntu/.pi`. Its `agent/{models,auth,settings}.json` hold pi's models, API keys,
> and behavior, bootstrapped from the host's `~/.pi/agent/` on first run. Per-workspace state lives under
> `~/.pi/pipod/workspaces/<ws>/` (`sessions/`, and optionally an `agent/` override).

## How `pipod` works

- **Container name**: `pipod-<sanitized_workspace_path>` (or `pipod-<sanitized_workspace_path>-nonet` with
  `--no-network`), derived from the invocation directory (`WORKSPACE_DIR="$(pwd)"`). Network mode is encoded in the
  name, so each workspace has two independent containers — one with Internet, one isolated — that share workspace &
  config but keep their own installed packages; switching `-nn` just uses the other container. `PROJECT_DIR` is where
  the `pipod` script lives.
- **Mounts** (set at `docker run`):
    - `$WORKSPACE_DIR` → `/workspace` (project files; also the work dir)
    - `$CONFIG_DIR` (`$HOME/.pi/pipod`) → `/home/ubuntu/.pi` (shared config)
    - `$CONFIG_DIR/workspaces/<ws>/agent` → `/home/ubuntu/.pi/agent` (per-workspace config override, only if the
      `agent/` dir exists)
    - `$CONFIG_DIR/workspaces/<ws>/sessions` → `/home/ubuntu/.pi/agent/sessions` (per-workspace sessions)
- **Env**: `PI_CODING_AGENT_DIR=/home/ubuntu/.pi/agent`.
- **User**: runs as `ubuntu`, uid/gid remapped to the host user via `--build-arg HOST_UID`/`HOST_GID`, so files written
  in the container are owned by the host user.
- **Reuse vs recreate**: `./pipod` reuses an existing container for the workspace (`docker start -ai`); `./pipod -r`
  force-recreates it. The image is rebuilt on every run (layer-cached, so cheap when unchanged).
- **Config bootstrap**: on run, if `~/.pi/pipod/agent/models.json` or `auth.json` is missing, it's copied from the
  host's `~/.pi/agent/` with `localhost`/`127.0.0.1` rewritten to `host.docker.internal`. The same bootstrap also
  applies inside `~/.pi/pipod/workspaces/<ws>/agent/` if that directory exists.

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
shared `~/.pi/pipod/agent` dir and the per-workspace `~/.pi/pipod/workspaces/<ws>/sessions` dir, and bootstraps
`models.json`/`auth.json` from the host if missing.

## Commands

```bash
./pipod        # build image, reuse or create container, run pi
./pipod -r     # force recreate the container (image rebuilt from cache)
```

## Conventions & guardrails

- **All state is host-side**: both the shared config and the per-workspace `workspaces/` state live at
  `~/.pi/pipod/` (outside the repo, never baked into the image; runtime bind-mounts). Don't rely on any of it being
  baked into the image.
- **Don't break UID/GID mapping**: the `--build-arg HOST_UID`/`HOST_GID` + `USER ubuntu` setup is what makes host-owned
  files writable in the container. Preserve it.
- **This repo wraps pi, it doesn't fork it**: behavior changes to pi itself belong upstream, or in pi
  config/extensions — not as patches here.
