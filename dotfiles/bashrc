# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# don't put duplicate lines in the history. See bash(1) for more options
# ... or force ignoredups and ignorespace
HISTCONTROL=ignoredups:ignorespace

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support for grep
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# Let eza use its own Catppuccin Frappé theme (~/.config/eza/theme.yml) instead
# of the dircolors LS_COLORS set above.
unset LS_COLORS

# Terminal capability: the container (and zellij's panes) don't advertise
# truecolour — COLORTERM is unset and TERM is only xterm-256color — so tools
# see a 256-colour terminal and approximate the Catppuccin Frappé hex palette
# instead of emitting it faithfully. Advertise truecolour for every tool that
# honours it (pi, jjui, opencode, leaf, …).
export COLORTERM=truecolor

# fzf: Catppuccin Frappé colours
export FZF_DEFAULT_OPTS="--color=bg+:#414559,bg:#303446,spinner:#f2d5cf,hl:#e78284,fg:#c6d0f5,header:#e78284,info:#ca9ee6,pointer:#f2d5cf,marker:#babbf1,fg+:#c6d0f5,prompt:#ca9ee6,hl+:#e78284,selected-bg:#51576d,border:#737994,label:#c6d0f5"

# modern defaults: eza for ls, bat for cat
alias ls='eza'
alias ll='eza -l --git'
alias la='eza -la'
alias lt='eza --tree'
alias cat='bat --paging=never'

# git tooling: lazygit TUI and workmux worktrees. workmux picks its multiplexer
# from the environment, and the zellij started below sets $ZELLIJ.
alias lg='lazygit'
alias wm='workmux'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
#if [ -f /etc/bash_completion ] && ! shopt -oq posix; then
#    . /etc/bash_completion
#fi

export EDITOR=nvim
export VISUAL=nvim

# mise: use an explicit path because this runs before mise is on PATH.
# $HOME/.local/bin is the per-user install (as in the Docker image); fall back
# to PATH for a system-wide install.
if [ -x "$HOME/.local/bin/mise" ]; then
    eval "$("$HOME"/.local/bin/mise activate bash)"
    eval "$("$HOME"/.local/bin/mise completion bash)"
elif command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
    eval "$(mise completion bash)"
fi
eval "$(starship init bash)"
eval "$(carapace _carapace bash)"
eval "$(atuin init bash)"
eval "$(zoxide init bash)"

zellij
