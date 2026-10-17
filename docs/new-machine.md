# New machine

Set up a fresh machine from this repo.

## Prerequisites

Install [mise](https://mise.jdx.dev/getting-started.html):

```sh
curl https://mise.run | sh
```

## Install the dotfiles

```sh
# Clone with jj (or `git clone`, which works on this colocated repo)
jj git clone <repo-url> ~/src/dotfiles
cd ~/src/dotfiles

mise trust              # project configs are ignored until trusted
mise install            # install the CLI tools from [tools]
mise dot apply --dry-run # preview the symlinks
mise dot apply          # deploy the dotfiles
mise dot status         # confirm: "N entries up to date"
```

Deploying `bat/` is not enough on its own: bat caches themes in `~/.cache/bat`,
so build the cache once after the dotfiles are in place:

```sh
bat cache --build            # or: mise exec -- bat cache --build
```

The Docker image does this at build time.

Set nvim (installed via mise) as git's default editor:

```sh
git config --global core.editor nvim
```

Activate mise in your shell (already done if you copied the tracked
`~/.bashrc`), then open a new shell.

## One-shot bootstrap

`mise bootstrap` can chain the whole setup (repos, tools, dotfiles) in one
command:

```sh
mise bootstrap              # run the steps declared in the config
mise bootstrap dotfiles     # only the dotfiles step
```

Adopting dotfiles straight from a remote repo:

```sh
mise bootstrap --adopt <user>/<repo>
```

## Notes and troubleshooting

| Symptom | Cause / fix |
| ------- | ----------- |
| `mise dot status` shows nothing / `[dotfiles]` ignored | Run inside the repo, use `mise -C /workspace dot status`, and make sure it is trusted (`mise trust`). |
| Symlink is broken, or status says `differs (symlink points to …)` | Re-run `mise dot apply` — it rewrites links to absolute paths. |
| A tracked config turns back into a regular file, or edits stop reaching the repo | Some apps replace their config **atomically** (write temp + rename), which breaks the symlink. Re-run `mise dot apply`, or switch that entry to `mode = "copy"` and use `mise dot add --changed` to write edits back. Known cases: `opencode/cli.json`, `pi/settings.json`, and `workmux/config.yaml` (workmux rewrites it when you cycle the dashboard theme with `T`). |
| A target is a regular file instead of a symlink | The entry exists but was not applied; run `mise dot apply`. |
| `capture is unavailable: git not found` | Install git (it is not in the mise registry): `apt-get install -y git`. |
| Editing a file does not change the repo | Check the mode; with `copy` mode run `mise dot add --changed`. |
| `mise: command not found` in a new shell | Add `eval "$(mise activate bash)"` to `~/.bashrc` (this repo's `bashrc` already does). |
| `bat` shows its default theme | The theme cache is stale or missing: run `bat cache --build`. |
| Colours look washed out or 256-colour approximated in `pi`/`jjui`/`opencode`/`leaf` | The container does not advertise truecolour (`COLORTERM` unset, `TERM=xterm-256color`). `bashrc` exports `COLORTERM=truecolor`; make sure the shell sources this `bashrc` and the tool inherits it. |
| `eza` shows dircolors colours, not Catppuccin Frappé | `LS_COLORS` is overriding the theme — `bashrc` unsets it, so make sure your shell actually sources this `bashrc`. |

## What gets deployed where

| Target                        | Source              |
| ----------------------------- | ------------------- |
| `~/.bashrc`                   | `bashrc`            |
| `~/.config/atuin/config.toml` | `atuin/config.toml` |
| `~/.config/bat` (`symlink-each`) | `bat`            |
| `~/.config/eza/theme.yml`     | `eza/theme.yml`     |
| `~/.config/hunk/config.toml`  | `hunk/config.toml`  |
| `~/.config/jjui` (`symlink-each`) | `jjui`          |
| `~/.config/lazygit/config.yml` | `lazygit/config.yml` |
| `~/.config/leaf` (`symlink-each`) | `leaf`          |
| `~/.config/opencode/cli.json` | `opencode/cli.json` |
| `~/.config/opencode/opencode.json` | `opencode/opencode.json` |
| `~/.config/procs/config.toml` | `procs/config.toml` |
| `~/.config/starship.toml`     | `starship.toml`     |
| `~/.config/workmux/config.yaml` | `workmux/config.yaml` |
| `~/.config/yazi` (`symlink-each`) | `yazi`          |
| `~/.config/zellij/config.kdl` | `zellij/config.kdl` |
| `~/.pi/agent` (`symlink-each`) | `pi`               |
