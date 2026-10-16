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
- `symlink-each` — link each file inside a source **directory** separately,
  leaving the target a real directory. Use this when other tools write into the
  same directory. Accepts `exclude`, `manifest`, `dot_prefix`, and `relative`.
- `copy` — keep a real file at the target; useful when an app rewrites it.
  Copy changes back to the repo with `mise dot add --changed`.
- `template` — generate a machine-specific file from a template.

### Deploy a whole directory

`source` may be a directory, so one entry can cover a tree instead of one entry
per file — the Yazi config in this repo does exactly that:

```toml
[dotfiles]
"~/.config/yazi" = { source = "yazi", mode = "symlink-each" }
```

`mise dot apply` walks `yazi/` and links every file it finds. There is no glob
in the **target** (targets are concrete paths); globs are used to filter the
walk instead, via `exclude` (skipped) and `include` (tracked directories only):

```toml
"~/.config/yazi" = {
  source = "yazi",
  mode = "symlink-each",
  exclude = ["*.md", ".git"],
}
```

Patterns are relative to the entry's directory, `*` does not cross `/`, `**`
does, and a pattern matching a directory covers everything beneath it. To deploy
a whole tree but hand out only parts of it to a given machine, use
[dotfile groups](https://mise.jdx.dev/dotfiles/groups.html)
(`[dotfile_groups]`) instead of a plain entry.

## Edit a dotfile

Edit it directly (`$EDITOR ~/.bashrc`) and commit the change with jj — the
symlink means the repo file is already updated:

```sh
jj status
jj commit -m "bashrc: add starship prompt"
```

## Commit and push to GitHub (jj)

This is a [Jujutsu](https://jj-vcs.dev/) repo colocated with Git, and `origin`
points at the GitHub remote. jj has no branches of its own — the Git branch
`main` is a **bookmark** that tracks its `main@origin` counterpart. The everyday
loop is:

```sh
cd /workspace

jj status                     # what changed in the working copy
jj commit -m "docs: …"        # save the working copy as a commit, start a new one
jj bookmark set main -r @-    # point main at the commit you just made
jj git push --bookmark main   # push main (and its ancestors) to origin
```

After a push jj may warn that the working-copy commit became immutable; that is
normal — it creates a fresh empty `@` to keep working in.

For the rest — authenticating with `gh`, creating the repo, bookmark tracking,
and recovering from rejected pushes — see **[Jujutsu and GitHub](./jj.md)**.

## Remove a dotfile

1. Delete its `[dotfiles]` entry from `mise.toml`.
2. Remove the deployed link and, if you want, the source:

```sh
mise dot unapply ~/.bashrc     # removes the deployed target
```

## Shell history (atuin)

`~/.config/atuin/config.toml` is managed here, so the settings are versioned.
Atuin runs in **local-only** mode (`auto_sync = false`, no sync login): history
is kept in the SQLite database at `~/.local/share/atuin/history.db`, which is
not tracked by this repo. The bash key binding (Ctrl-R) comes from
`eval "$(atuin init bash)"` in the tracked `bashrc`.

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
