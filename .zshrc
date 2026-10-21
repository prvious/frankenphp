# Environment
. /etc/profile.d/.env

# Path configuration
export PATH="$HOME/.local/bin:$PATH"

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# Load the development shell framework
export ZSH="$HOME/.oh-my-zsh"
if [[ ! -r "$ZSH/oh-my-zsh.sh" ]]; then
    print -u2 "Missing Oh My Zsh installation: $ZSH"
    return 1
fi

ZSH_THEME=""
zstyle ':omz:update' mode disabled
plugins=(
    git
    aws
    gh
    zsh-autosuggestions
    fzf-tab
    fast-syntax-highlighting
)
source "$ZSH/oh-my-zsh.sh"

# Tool initializations (synchronous - needed for prompt)
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

# FZF integration
if [[ -t 0 && -t 1 ]]; then
    source <(fzf --zsh)
fi

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
zstyle ':fzf-tab:complete:(ls|l|ll|la|lt|eza):*' fzf-preview '[[ -d $realpath ]] && eza -1 --color=always --icons $realpath || cat $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'
