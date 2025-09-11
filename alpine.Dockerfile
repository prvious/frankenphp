ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS base

LABEL maintainer="Clovis Muneza"
LABEL org.opencontainers.image.source="https://github.com/prvious/frankenphp"

ARG WWWGROUP=1000
ARG WWWUSER=1000
ARG USER=deploy

ENV TZ=UTC
ENV SERVER_NAME=:80
ENV FNM_DIR=/usr/local/fnm
ENV PATH=/usr/bin:$PATH

COPY ./env.sh /etc/profile.d/env.sh

RUN apk add --no-cache bash curl wget gnupg supervisor git unzip postgresql-client mysql-client zsh \
    && sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Set bash as the shell now that it's installed
SHELL [ "/bin/bash", "-l", "-exo", "pipefail", "-c" ]

RUN apk add --no-cache nodejs npm jpegoptim optipng pngquant gifsicle libavif ffmpeg \
    && echo 'source /etc/profile.d/env.sh' >> /etc/bash.bashrc \
    && node --version && npm --version \
    && npm install -g npm pnpm svgo \
    && install-php-extensions @composer mysqli pdo_mysql pgsql pdo_pgsql bcmath gd imagick imap pcntl zip intl exif ftp xml pdo_sqlsrv sqlsrv sockets \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini" \
    && addgroup -g $WWWGROUP ${USER} \
    && adduser -D -s /bin/zsh -G ${USER} -u ${WWWUSER} ${USER} \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chown -R ${USER}:${USER} /data/caddy && chown -R ${USER}:${USER} /config/caddy && chown -R ${USER}:${USER} /app \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS dev

RUN install-php-extensions xdebug \
    && apk add --no-cache wget tar gzip \
    && ARCH=$(uname -m) \
    && case $ARCH in \
        x86_64) GITHUB_ARCH="linux_amd64" ;; \
        aarch64) GITHUB_ARCH="linux_arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac \
    && wget -O /tmp/gh.tar.gz "https://github.com/cli/cli/releases/latest/download/gh_$(wget -qO- https://api.github.com/repos/cli/cli/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')_${GITHUB_ARCH}.tar.gz" \
    && tar -xzf /tmp/gh.tar.gz -C /tmp \
    && cp /tmp/gh_*/bin/gh /usr/local/bin/ \
    && chmod +x /usr/local/bin/gh \
    && rm -rf /tmp/gh* \
    && apk add --no-cache htop nano zsh-autosuggestions zsh-syntax-highlighting fontconfig \
    && curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    && case $ARCH in \
        x86_64) EZA_ARCH="x86_64-unknown-linux-musl" ;; \
        aarch64) EZA_ARCH="aarch64-unknown-linux-musl" ;; \
    esac \
    && (wget -qO /tmp/eza.tar.gz "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" \
        && tar -xzf /tmp/eza.tar.gz -C /usr/local/bin \
        && rm /tmp/eza.tar.gz) || echo "Failed to install eza, continuing without it" \
    && curl --retry 5 --retry-delay 5 -fsSL https://opencode.ai/install | bash \
    && mkdir -p /usr/share/fonts/nerd-fonts \
    && wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O /tmp/JetBrainsMono.zip \
    && unzip /tmp/JetBrainsMono.zip -d /usr/share/fonts/nerd-fonts/JetBrainsMono \
    && rm /tmp/JetBrainsMono.zip \
    && fc-cache -fv \
    && rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

    # Switch to the deploy user to install Oh My Zsh and plugins
USER ${USER}
    
    # Install Oh My Zsh first, then custom plugins
    RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended \
    && git clone --depth 1 https://github.com/junegunn/fzf.git /home/${USER}/.fzf \
    && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git ${ZSH_CUSTOM:-/home/$USER/.oh-my-zsh/custom}/plugins/zsh-autosuggestions \
    && git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-/home/$USER/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting \
    && git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git ${ZSH_CUSTOM:-/home/$USER/.oh-my-zsh/custom}/plugins/fast-syntax-highlighting \
    && git clone --depth 1 -- https://github.com/marlonrichert/zsh-autocomplete.git ${ZSH_CUSTOM:-/home/$USER/.oh-my-zsh/custom}/plugins/zsh-autocomplete \
    && git clone --depth 1 https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-/home/$USER/.oh-my-zsh/custom}/plugins/fzf-tab \
    && curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
    && /home/${USER}/.fzf/install

# Switch back to root for final setup
USER root
COPY  --chown=${USER}:${USER} ./.zshrc /home/${USER}/.zshrc
USER ${USER}

WORKDIR /app
USER ${USER}


#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    
FROM base AS prod

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

WORKDIR /app
USER ${USER}