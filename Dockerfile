# syntax=docker/dockerfile:1
ARG DEBIAN_SUITE=trixie
ARG GO_VERSION=1.27

FROM golang:${GO_VERSION}-${DEBIAN_SUITE} AS go-toolchain

# Common Debian base for the source build and the final runtime.
FROM debian:${DEBIAN_SUITE}-slim AS php-build-base
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]
ENV PHPIZE_DEPS="autoconf dpkg-dev file g++ gcc libc-dev make pkg-config re2c" \
    PHP_INI_DIR=/usr/local/etc/php \
    PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64" \
    PHP_LDFLAGS="-Wl,-O1 -pie"
ENV PHP_CPPFLAGS="${PHP_CFLAGS}"

# Retain the PHP extension toolchain for existing downstream Dockerfiles;
# prevent distro PHP packages from accidentally introducing a second PHP ABI.
RUN printf 'Package: php*\nPin: release *\nPin-Priority: -1\n' > /etc/apt/preferences.d/no-debian-php \
    && apt-get update \
    && apt-get install -y --no-install-recommends $PHPIZE_DEPS ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*

FROM php-build-base AS php-builder
ARG DEBIAN_SUITE
ARG VERSION=8.5-trixie
ARG PHP_VERSION=""
ARG PHP_SHA256=""

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gpg gpgv libargon2-dev libcurl4-openssl-dev libonig-dev \
        libreadline-dev libsodium-dev libsqlite3-dev libssl-dev libxml2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=755 docker/php-helpers/docker-php-* /usr/local/bin/
COPY docker/php-helpers/LICENSE /usr/local/share/licenses/docker-php-helpers/LICENSE
RUN --mount=type=bind,source=docker/build-php.sh,target=/build-php.sh bash /build-php.sh

FROM php-builder AS frankenphp-builder
ARG FRANKENPHP_VERSION=""
ARG FRANKENPHP_REVISION=""
COPY --from=go-toolchain /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}" GOTOOLCHAIN=local
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake git jq libbrotli-dev \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=docker/build-frankenphp.sh,target=/build-frankenphp.sh \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOPATH=/go bash /build-frankenphp.sh

FROM php-build-base AS frankenphp-base
ARG PHP_VERSION
ARG PHP_SHA256
ARG FRANKENPHP_VERSION
ARG FRANKENPHP_REVISION
ENV PHP_VERSION="${PHP_VERSION}" \
    PHP_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz" \
    PHP_ASC_URL="https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz.asc" \
    PHP_SHA256="${PHP_SHA256}" \
    FRANKENPHP_VERSION="${FRANKENPHP_VERSION}" \
    GODEBUG=cgocheck=0 \
    XDG_CONFIG_HOME=/config \
    XDG_DATA_HOME=/data

LABEL org.opencontainers.image.php.version="${PHP_VERSION}" \
    org.opencontainers.image.frankenphp.version="${FRANKENPHP_VERSION}" \
    org.opencontainers.image.frankenphp.revision="${FRANKENPHP_REVISION}"

RUN --mount=type=bind,from=php-builder,source=/out/php-runtime-packages,target=/php-runtime-packages \
    apt-get update \
    && xargs -r apt-get install -y --no-install-recommends libbrotli1 libcap2-bin libstdc++6 mailcap < /php-runtime-packages \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 1777 -o www-data -g www-data /var/www/html \
    && mkdir -p /config/caddy /data/caddy

COPY --link --from=php-builder /usr/local/ /usr/local/
COPY --link --from=php-builder /usr/src/php.tar.xz /usr/src/php.tar.xz
COPY --link --chmod=755 docker/docker-php-entrypoint /usr/local/bin/docker-php-entrypoint

# Copy and set the capability in one layer so the binary is not duplicated.
RUN --mount=type=bind,from=frankenphp-builder,source=/out/frankenphp,target=/frankenphp-build \
    cp -a /frankenphp-build/. / \
    && ldconfig \
    && setcap cap_net_bind_service=+ep /usr/local/bin/frankenphp \
    && php --version \
    && frankenphp version

WORKDIR /app
EXPOSE 80 443 443/udp 2019
HEALTHCHECK CMD curl -fsS http://localhost:2019/metrics || exit 1
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["--config", "/etc/frankenphp/Caddyfile", "--adapter", "caddyfile"]

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

# Install shared runtime packages and image tools from the target Debian suite.
# A refresh also upgrades all existing runtime packages from the configured repositories.
RUN echo "${REFRESH}" > /dev/null \
    && apt-get update \
    && apt-get upgrade -y --no-install-recommends \
        -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
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

# Keep the existing extension installer, independently of any upstream PHP image.
RUN curl --retry 3 -fsSL \
        https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions \
        -o /usr/local/bin/install-php-extensions \
    && chmod 0755 /usr/local/bin/install-php-extensions \
    && install-php-extensions \
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

# Copy runtime configuration and major-channel artifacts after the expensive package layers.
# --link makes each layer independent of the ones below it, so a refresh of the
# package layers keeps these (Node alone is 51 MB compressed) and nodes that run
# the image need not pull them again.
COPY --link ./.env /etc/profile.d/.env
COPY --link --chown=0:0 --chmod=755 ./usr/local/bin/* /usr/local/bin/
COPY --link --from=composer-builder --chown=0:0 --chmod=755 /usr/bin/composer /usr/bin/composer
COPY --link --from=node-builder --chown=0:0 --chmod=755 /usr/local/bin/node /usr/local/bin/node
COPY --link --from=node-builder --chown=0:0 /usr/local/lib/node_modules/pnpm /usr/local/lib/node_modules/pnpm
COPY --link --from=node-builder --chown=0:0 /usr/local/lib/node_modules/svgo /usr/local/lib/node_modules/svgo

# User creation and permissions. frankenphp-base already grants the binary
# cap_net_bind_service to serve port 80 as the runtime user.
RUN ln -s ../lib/node_modules/pnpm/bin/pnpm.mjs /usr/local/bin/pnpm \
    && ln -s ../lib/node_modules/pnpm/bin/pnpx.mjs /usr/local/bin/pnpx \
    && ln -s ../lib/node_modules/svgo/bin/svgo.js /usr/local/bin/svgo \
    && groupadd --non-unique -g "${WWWGROUP}" "${USER}" \
    && useradd -m --no-user-group -o -g "${WWWGROUP}" -u "${WWWUSER}" -s /bin/zsh "${USER}" \
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
ARG ZOXIDE_VERSION
ARG STARSHIP_VERSION=latest
ARG OPENCODE_VERSION

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
        | sh -s -- --yes --bin-dir /usr/local/bin --version "${STARSHIP_VERSION}" \
    && case "${TARGETARCH}" in \
        amd64) OPENCODE_ARCH="x64"; ZOXIDE_ARCH="x86_64" ;; \
        arm64) OPENCODE_ARCH="arm64"; ZOXIDE_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && if [ -n "${ZOXIDE_VERSION}" ]; then \
        mkdir -p /tmp/zoxide /usr/local/share/man/man1 \
        && curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION#v}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" \
            | tar -xz -C /tmp/zoxide \
        && install -m 0755 /tmp/zoxide/zoxide /usr/local/bin/zoxide \
        && cp /tmp/zoxide/man/man1/* /usr/local/share/man/man1/ \
        && rm -rf /tmp/zoxide; \
    else \
        curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh \
            | sh -s -- --bin-dir /usr/local/bin --man-dir /usr/local/share/man; \
    fi \
    && if [ -n "${OPENCODE_VERSION}" ]; then \
        OPENCODE_RELEASE="download/${OPENCODE_VERSION}"; \
    else \
        OPENCODE_RELEASE="latest/download"; \
    fi \
    && curl -fsSL "https://github.com/anomalyco/opencode/releases/${OPENCODE_RELEASE}/opencode-linux-${OPENCODE_ARCH}.tar.gz" \
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

# Production PHP defaults, read by conf.d/10-production.ini. An app overrides any
# of them by setting the variable on its container. The names follow the
# serversideup/php images.
ENV PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=256 \
    PHP_OPCACHE_INTERNED_STRINGS_BUFFER=32 \
    PHP_OPCACHE_MAX_ACCELERATED_FILES=32531 \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_OPCACHE_REVALIDATE_FREQ=2 \
    PHP_REALPATH_CACHE_SIZE=4096K \
    PHP_REALPATH_CACHE_TTL=600 \
    PHP_SESSION_UPLOAD_PROGRESS_ENABLED=0

# Use production PHP configuration
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY --link ./usr/local/etc/php/conf.d/10-production.ini /usr/local/etc/php/conf.d/10-production.ini

# Copy production zshrc
COPY --chown=${USER}:${USER} ./.zshrc.prod /home/${USER}/.zshrc

# Switch to the runtime user and validate the plain production shell
USER ${USER}

RUN zsh -i -c 'exit 0'

WORKDIR /app
