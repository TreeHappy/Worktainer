# Usage

How to work with the dotfiles in this repo.

## How it works

The repo stores the **sources**. Each entry in `mise.toml` maps a target in
`$HOME` to a source in the repo:

```toml
[dotfiles]
"~/.bashrc" = { source = "bashrc" }
"~/.config/zellij/config.kdl" = { source = "zellij/config.kdl" }
```

`mise dot apply` makes the target a symlink to the source. Relative sources
resolve from the directory of the config file that declares them (the repo
root here), so entries always deploy to the same absolute paths.

The default mode is `symlink` (from `mise settings dotfiles.default_mode`), so:

- Editing `~/.bashrc` edits `./bashrc` in the repo — they are the same file.
  Content changes need **no** re-apply.
- `mise dot apply` is only needed when targets are added/removed, or on a new
  machine.

## Everyday commands

```sh
cd /workspace

mise dot status            # what is applied / differs / missing
mise dot apply --dry-run   # preview changes without writing
mise dot apply             # create or fix symlinks
mise dot diff              # show differences for copy-mode entries
```

Run them from anywhere with `mise -C /workspace dot <command>`.

## Add a new dotfile

```sh
cd /workspace
mise dot add --local --source <source-in-repo> <target-in-home>
```

For example, to start managing a Zellij layouts folder:

```sh
mise dot add --local --source zellij/layouts ~/.config/zellij/layouts
```

`mise dot add` moves the target into the repo, writes the `[dotfiles]` entry to
the repo's `mise.toml`, and applies it.

Flags worth knowing:

| Flag                  | Purpose                                                           |
| --------------------- | ----------------------------------------------------------------- |
| `--local`             | Write the entry to this repo's `mise.toml` (not the global config) |
| `--source <path>`     | Where the source is stored, relative to the repo root              |
| `--mode <mode>`       | `symlink` (default), `symlink-each`, `copy`, or `template`         |
| `--dry-run`           | Preview without writing                                            |

> Always pass `--local` in this repo. Without it, `mise dot add` writes to your
> global config (`~/.config/mise/config.toml`), which is not versioned here.

### Choosing a mode

- `symlink` (default) — link a file or an entire directory into place.
- `copy` — keep a real file at the target; useful when an app rewrites it.
  Copy changes back to the repo with `mise dot add --changed`.
- `template` — generate a machine-specific file from a template.

## Edit a dotfile

Edit it directly (`$EDITOR ~/.bashrc`) and commit the change with jj — the
symlink means the repo file is already updated:

```sh
jj status
jj commit -m "bashrc: add starship prompt"
```

## Remove a dotfile

1. Delete its `[dotfiles]` entry from `mise.toml`.
2. Remove the deployed link and, if you want, the source:

```sh
mise dot unapply ~/.bashrc     # removes the deployed target
```

## Sharing history between machines (optional)

Beyond plain git commits, mise can snapshot and sync dotfile history:

```sh
mise dot save                                  # checkpoint current files
mise dot origin set <repo-url> --sync sync     # connect a private git repo
```

To save automatically on every edit, add this to the global config
(`~/.config/mise/config.toml`) and run `mise bootstrap`:

```toml
[bootstrap.services.mise-history]
builtin = "history-watch"
```

History commands (`save`, `history`, `rollback`) need `git` on `PATH`.
