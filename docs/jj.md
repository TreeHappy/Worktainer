# Jujutsu (jj) and GitHub

This repo is a [Jujutsu](https://jj-vcs.dev/) repo **colocated with Git**
(`.jj` sits next to `.git`), and `origin` is its GitHub remote. jj does the
version control; [`gh`](https://cli.github.com/) handles GitHub authentication
and repo creation. They cooperate because jj speaks Git: the colocated `.git`
store and `gh`'s credential helper are all jj needs to push.

See [Tools](./tools.md) for how both are installed, and
[New machine](./new-machine.md) for cloning this repo onto a fresh box.

## Concepts in one minute

| Git | jj |
| --- | -- |
| branch `main` | **bookmark** `main` |
| remote-tracking `origin/main` | remote bookmark `main@origin` |
| `git add` + `git commit` | implicit — the working copy **is** a commit (`@`) |
| `git checkout`/`switch` | `jj new` / `jj edit` |

- **`@` is the working-copy commit.** Edit files and jj snapshots them into `@`
  automatically; there is no staging area and no `git add`.
- **A bookmark is jj's name for a Git branch.** A bookmark can *track* a remote
  bookmark (e.g. `main` tracks `main@origin`); only tracked bookmarks are pushed
  and fetched by default.
- **jj never switches branches.** You move around with `jj new`/`jj edit`, and
  `jj git push` sends the bookmark's commit and every commit it reaches.

## 1. Authenticate with gh

Once per machine:

```sh
gh auth login            # GitHub.com → HTTPS → login with a browser or token
gh auth status           # confirm you are logged in
gh auth setup-git        # install gh as git's credential helper
```

`gh auth setup-git` is the part that matters for jj: jj pushes through the
colocated Git store, which uses Git's credential helper, so this is what lets
`jj git push` authenticate silently instead of prompting for a username/token.

## 2. Create the GitHub repo with gh

From the repo root, create the repository and register it as `origin`:

```sh
gh repo create Worktainer --public --source=. --remote=origin
```

| Flag | Effect |
| ---- | ------ |
| `--public` / `--private` | visibility |
| `--source=.` | use the current directory as the source repo |
| `--remote=origin` | add the new GitHub URL as the `origin` remote |
| `--push` | also push — but it runs `git push`, so **prefer `jj git push`** below |

If the remote already exists (or you are adding it by hand), wire it up directly:

```sh
jj git remote add origin git@github.com:TreeHappy/Worktainer.git   # or https://…
jj git remote list
```

## 3. First push

```sh
jj git fetch                   # learn the remote's state
jj bookmark track main@origin  # once, if main@origin is not listed yet
jj bookmark set main -r @      # point main at your work (or at the commit you want)
jj git push -b main            # push main and its ancestors to origin
```

Check the result any time with:

```sh
jj bookmark list --all-remotes   # local, @git, and @origin positions
```

## 4. Everyday loop

```sh
cd /workspace

jj status                     # what changed in the working copy
jj commit -m "docs: …"        # finalize @ and start a fresh empty @
jj bookmark set main -r @-    # move main onto the commit you just made
jj git push -b main           # push main (and its ancestors) to origin
```

After a push jj may warn that the working-copy commit became immutable. That is
expected — it simply creates a new empty `@` to keep working in.

Handy variations:

| Task | Command |
| ---- | ------- |
| Push a bookmark and its ancestors | `jj git push -b main` (`-b` = `--bookmark`) |
| Push every bookmark and tag | `jj git push --all` |
| Push to a specific remote | `jj git push --remote origin -b main` |
| Compare local and remote | `jj bookmark list --all-remotes` |
| Fetch the latest remote state | `jj git fetch` |
| Move an existing bookmark | `jj bookmark move main --to @-` |

## 5. If a push is rejected

jj refuses to overwrite a remote that moved since your last fetch (similar to
`git push --force-with-lease`). Fetch and rebase onto the remote, then push:

```sh
jj git fetch
jj rebase -d main@origin     # replay your work on top of the remote
jj git push -b main
```

If you have a divergent bookmark, resolve it first — see jj's
[bookmark conflicts](https://docs.jj-vcs.dev/latest/bookmarks/#conflicts) docs.

## 6. Clone an existing repo

```sh
# jj clone (sets up origin and fetches in one step)
jj git clone git@github.com:TreeHappy/Worktainer.git ~/src/dotfiles

# …or attach jj to an existing plain `git clone`
git clone git@github.com:TreeHappy/Worktainer.git ~/src/dotfiles
cd ~/src/dotfiles
jj git init --colocate
```

After cloning, run the steps in [New machine](./new-machine.md) to install the
tools and deploy the dotfiles.

## Reference

- jj bookmarks — <https://docs.jj-vcs.dev/latest/bookmarks/>
- jj and GitHub — <https://docs.jj-vcs.dev/latest/github/>
- `gh repo create` — <https://cli.github.com/manual/gh_repo_create>
