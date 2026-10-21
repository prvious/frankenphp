ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS frankenphp-base

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BUILDER STAGES: Follow supported major release channels
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM node:26-bookworm-slim AS node-builder

ARG REFRESH

RUN echo "${REFRESH}" > /dev/null \
    && npm install --global pnpm@11 svgo

FROM composer:2 AS composer-builder

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BASE STAGE: FrankenPHP base with minimal dependencies
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM frankenphp-base AS base

SHELL [ "/bin/bash", "-l", "-exo", "pipefail", "-c" ]

LABEL maintainer="Clovis Muneza"
LABEL org.opencontainers.image.source="https://github.com/prvious/frankenphp"

ARG WWWGROUP=1000
ARG WWWUSER=1000
ARG USER=deploy
ARG REFRESH

ENV TZ=UTC
ENV SERVER_NAME=:80
ENV DEBIAN_FRONTEND=noninteractive
ENV pnpm_config_store_dir=/home/${USER}/.pnpm-store

# Install shared runtime packages and image tools from the target Debian suite
RUN echo "${REFRESH}" > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        ffmpeg \
        gifsicle \
        git \
        jpegoptim \
        libatomic1 \
        libavif-bin \
        optipng \
        pngquant \
        procps \
        supervisor \
        unzip \
        zsh \
    && . /etc/os-release \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /etc/apt/keyrings/postgresql.asc \
    && echo "0144068502a1eddd2a0280ede10ef607d1ec592ce819940991203941564e8e76  /etc/apt/keyrings/postgresql.asc" | sha256sum -c - \
    && echo "deb [signed-by=/etc/apt/keyrings/postgresql.asc] http://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-17 \
        default-mysql-client \
    && echo 'source /etc/profile.d/.env' >> /etc/bash.bashrc \
    && apt-get clean \
    && rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /var/lib/apt/lists/*

# PHP extensions
RUN install-php-extensions \
        mysqli \
        pdo_mysql \
        pgsql \
        pdo_pgsql \
        bcmath \
        gd \
        imagick \
        imap \
        pcntl \
        zip \
        intl \
        exif \
        ftp \
        xml \
        pdo_sqlsrv \
        sqlsrv \
        sockets

# Copy runtime configuration and major-channel artifacts after the expensive package layers
COPY ./.env /etc/profile.d/.env
COPY --chown=0:0 --chmod=755 ./usr/local/bin/* /usr/local/bin/
COPY --from=composer-builder --chown=0:0 --chmod=755 /usr/bin/composer /usr/bin/composer
COPY --from=node-builder --chown=0:0 --chmod=755 /usr/local/bin/node /usr/local/bin/node
COPY --from=node-builder --chown=0:0 /usr/local/lib/node_modules/pnpm /usr/local/lib/node_modules/pnpm
COPY --from=node-builder --chown=0:0 /usr/local/lib/node_modules/svgo /usr/local/lib/node_modules/svgo

# User creation and permissions
RUN ln -s ../lib/node_modules/pnpm/bin/pnpm.mjs /usr/local/bin/pnpm \
    && ln -s ../lib/node_modules/pnpm/bin/pnpx.mjs /usr/local/bin/pnpx \
    && ln -s ../lib/node_modules/svgo/bin/svgo.js /usr/local/bin/svgo \
    && groupadd --non-unique -g "${WWWGROUP}" "${USER}" \
    && useradd -m --no-user-group -o -g "${WWWGROUP}" -u "${WWWUSER}" -s /bin/zsh "${USER}" \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && mkdir -p \
        "/home/${USER}/.config/psysh" \
        "/home/${USER}/.local/bin" \
        "/home/${USER}/.pnpm-store" \
        /app \
        /data/opencode \
        /config/opencode \
    && chown -R "${USER}:${USER}" \
        "/home/${USER}" \
        /app \
        /data/caddy \
        /data/opencode \
        /config/caddy \
        /config/opencode

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# DEV STAGE
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS dev

ARG REFRESH
ARG TARGETARCH

# Install current development tools through their supported release channels
RUN echo "${REFRESH}" > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        gnupg \
        htop \
        nano \
    && install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
        | gpg --dearmor -o /etc/apt/keyrings/eza.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/eza.gpg] http://deb.gierens.de stable main" > /etc/apt/sources.list.d/eza.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        eza \
        gh \
    && git clone --depth 1 https://github.com/junegunn/fzf.git /tmp/fzf \
    && /tmp/fzf/install --bin \
    && install -m 0755 /tmp/fzf/bin/fzf /usr/local/bin/fzf \
    && curl -fsSL https://raw.githubusercontent.com/starship/starship/master/install/install.sh \
        | sh -s -- --yes --bin-dir /usr/local/bin \
    && curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
        | sh -s -- --bin-dir /usr/local/bin --man-dir /usr/local/share/man \
    && case "${TARGETARCH}" in \
        amd64) OPENCODE_ARCH="x64" ;; \
        arm64) OPENCODE_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${OPENCODE_ARCH}.tar.gz" \
        | tar -xz -C /usr/local/bin \
    && apt-get clean \
    && rm -rf /tmp/fzf /var/lib/apt/lists/*

# Development PHP extensions
RUN install-php-extensions xdebug \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# Copy development shell configuration
COPY --chown=${USER}:${USER} ./.zshrc /home/${USER}/.zshrc

# Switch to the runtime user and install the development shell plugins
USER ${USER}

RUN git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "/home/${USER}/.oh-my-zsh" \
    && git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions.git "/home/${USER}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    && git clone --depth 1 https://github.com/Aloxaf/fzf-tab.git "/home/${USER}/.oh-my-zsh/custom/plugins/fzf-tab" \
    && git clone --depth 1 https://github.com/zdharma-continuum/fast-syntax-highlighting.git "/home/${USER}/.oh-my-zsh/custom/plugins/fast-syntax-highlighting" \
    && starship preset no-nerd-font -o "/home/${USER}/.config/starship.toml" \
    && zsh -i -c 'exit 0' \
    && gh --version \
    && eza --version \
    && fzf --version \
    && opencode --version \
    && starship --version \
    && zoxide --version

WORKDIR /app

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# PROD STAGE
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS prod

# Use production PHP configuration
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Copy production zshrc
COPY --chown=${USER}:${USER} ./.zshrc.prod /home/${USER}/.zshrc

# Switch to the runtime user and validate the plain production shell
USER ${USER}

RUN zsh -i -c 'exit 0'

WORKDIR /app
