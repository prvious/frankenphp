export XDG_CONFIG_HOME=$HOME/.config
export XDG_DATA_HOME=$HOME/.data
export XDG_CACHE_HOME=$HOME/.cache
export XDG_STATE_HOME=$HOME/.state
export PNPM_STORE_PATH=${XDG_DATA_HOME}/pnpm-store

mkdir -p $XDG_CONFIG_HOME $XDG_DATA_HOME $XDG_CACHE_HOME $XDG_STATE_HOME $PNPM_STORE_PATH

alias pint="./vendor/bin/pint"
alias pa="php artisan"
alias stan="./vendor/bin/phpstan"
alias phpstan="./vendor/bin/phpstan"
alias pest="./vendor/bin/pest"
alias amf="php artisan migrate:fresh"
alias amfs="php artisan migrate:fresh --seed"