# Environment
. /etc/profile.d/.env

# Path configuration (must be before tools that depend on it)
export PATH="$HOME/.local/bin:$HOME/.fzf/bin:$HOME/.opencode/bin:$PNPM_HOME:$PATH"

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Zinit installation
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# Completions path
export FPATH="$HOME/.eza/completions/zsh:$FPATH"

# Essential plugins (loaded immediately)
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# OMZ libs (only essential ones, loaded with turbo)
zinit wait lucid for \
    OMZL::git.zsh \
    OMZL::completion.zsh

# OMZ plugins (turbo mode - deferred loading)
zinit wait lucid for \
    OMZP::git \
    OMZP::aws \
    OMZP::gh

# Syntax highlighting (load last, with turbo)
zinit wait lucid for \
    atinit"zicompinit; zicdreplay" \
    zdharma-continuum/fast-syntax-highlighting

# Tool initializations (synchronous - needed for prompt)
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

# FZF (turbo)
zinit wait lucid for \
    atload"source <(fzf --zsh)" \
    zdharma-continuum/null

# Eza aliases (immediate, not deferred)
alias l='eza -lah --icons --git --group-directories-first'
alias ll='eza -lh --icons --git --group-directories-first'
alias la='eza -lah --icons --git --group-directories-first'
alias ls='eza --icons --group-directories-first'
alias lt='eza --tree --icons --git --group-directories-first'

# Keybindings
bindkey -e
bindkey ';5A' history-search-backward
bindkey ';5B' history-search-forward
bindkey ';5C' forward-word
bindkey ';5D' backward-word
bindkey '^[[3~' delete-char

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase

setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Docker completion stacking
zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# Completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu select

# FZF-tab styling
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza --color --icons $realpath'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always --icons $realpath'
zstyle ':fzf-tab:complete:(ls|l|ll|la|lt|eza):*' fzf-preview '[[ -d $realpath ]] && eza -1 --color=always --icons $realpath || bat --color=always --style=numbers $realpath 2>/dev/null || cat $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'

