. /etc/profile.d/env.sh

# Oh My Zsh configuration
export ZSH="$HOME/.oh-my-zsh"
export FZF_HOME="${HOME}/.local/share/fzf"

# Path configuration
export PATH="$HOME/.local/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.opencode/bin:$PATH"

# Load completions
fpath=($HOME/.eza/completions/zsh $fpath)
autoload -Uz compinit
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
    compinit;
else
    compinit -C;
fi;

# Eza aliases
alias ls='eza --color=always --group-directories-first'
alias ll='eza -la --color=always --group-directories-first'
alias la='eza -a --color=always --group-directories-first'
alias lt='eza -aT --color=always --group-directories-first'

source <(fzf --zsh)

# Oh My Zsh plugins (only the specified ones)
plugins=(git zsh-autosuggestions zsh-syntax-highlighting fast-syntax-highlighting aws gh zoxide fzf fzf-tab)
# zsh-syntax-highlighting fast-syntax-highlighting zsh-autocomplete 

source $ZSH/oh-my-zsh.sh

# Keybindings
bindkey -e
bindkey ';5A' history-search-backward
bindkey ';5B' history-search-forward
bindkey ";5C" forward-word
bindkey ";5D" backward-word
bindkey "^[[3~" delete-char

# History configuration
HISTSIZE=500
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

# Completion styling

# fzf-tab configuration
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*:git-checkout:*' sort false
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:*' fzf-flags --color=fg:1,fg+:2 --bind=tab:accept
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' switch-group '<' '>'



# FNM environment (if available)
if command -v fnm >/dev/null 2>&1; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi


# Initialize starship prompt
eval "$(starship init zsh)"