ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS frankenphp-base

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BUILDER STAGE: Download pinned binaries and tools
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS binaries-builder

ARG TARGETARCH
ARG NODE_VERSION=26.5.1
ARG PNPM_VERSION=11.18.0
ARG SVGO_VERSION=4.0.2

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gzip \
        libatomic1 \
        tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/binaries

# Download Node.js without npm and verify the pinned archive
RUN case "${TARGETARCH}" in \
        amd64) NODE_ARCH="x64"; NODE_SHA256="2b07f09c218d473a26442bff5a90151f53f7b7c0a23bad244eda2c26303a2ba7" ;; \
        arm64) NODE_ARCH="arm64"; NODE_SHA256="21194bbf41c18d9ec277545c4d14cce8597d57a9d9f494c323d8121a25de33e8" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && NODE_ARCHIVE="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}" -o "${NODE_ARCHIVE}" \
    && echo "${NODE_SHA256}  ${NODE_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${NODE_ARCHIVE}" \
    && mkdir -p /tmp/binaries/node/bin \
    && mv "node-v${NODE_VERSION}-linux-${NODE_ARCH}/bin/node" /tmp/binaries/node/bin/ \
    && rm -rf "${NODE_ARCHIVE}" "node-v${NODE_VERSION}-linux-${NODE_ARCH}"

# Download pnpm's architecture-independent package and verify the pinned archive
RUN PNPM_ARCHIVE="pnpm-${PNPM_VERSION}.tgz" \
    && curl -fsSL "https://registry.npmjs.org/pnpm/-/${PNPM_ARCHIVE}" -o "${PNPM_ARCHIVE}" \
    && echo "29c35ca8d2a287988fdee3e0f36e07d9b93783f567b579b7fd5b798a4563dd81  ${PNPM_ARCHIVE}" | sha256sum -c - \
    && mkdir -p /tmp/binaries/pnpm \
    && tar -xzf "${PNPM_ARCHIVE}" -C /tmp/binaries/pnpm --strip-components=1 \
    && ln -s bin/pnpm.mjs /tmp/binaries/pnpm/pnpm \
    && rm -f "${PNPM_ARCHIVE}"

# Install a pinned svgo release using the verified Node.js and pnpm binaries
RUN mkdir -p /tmp/binaries/pnpm/bin /tmp/binaries/pnpm-global \
    && export PATH="/tmp/binaries/node/bin:/tmp/binaries/pnpm:/tmp/binaries/pnpm/bin:$PATH" \
    && export PNPM_HOME=/tmp/binaries/pnpm \
    && pnpm config set store-dir /tmp/pnpm-store --global \
    && pnpm config set global-dir /tmp/binaries/pnpm-global --global \
    && pnpm config set global-bin-dir /tmp/binaries/pnpm/bin --global \
    && pnpm add -g "svgo@${SVGO_VERSION}"

# Download and verify development-only binaries
FROM binaries-builder AS dev-binaries-builder

ARG EZA_VERSION=0.23.5
ARG FZF_VERSION=0.74.1
ARG GH_VERSION=2.96.0
ARG OPENCODE_VERSION=1.18.9
ARG STARSHIP_VERSION=1.26.0
ARG ZOXIDE_VERSION=0.10.0

RUN mkdir -p /tmp/binaries/dev \
    && case "${TARGETARCH}" in \
        amd64) \
            EZA_ARCH="x86_64"; EZA_SHA256="35c70c5c43c29108075e58b893234c67ef585f0b53a7eaf8e9e7d4eec9f339b4"; \
            FZF_ARCH="amd64"; FZF_SHA256="df53438be5f51e151bb4044d78fda72bdfe209e3ecd2baecae48e8dea370c81b"; \
            GH_ARCH="amd64"; GH_SHA256="83d5c2ccad5498f58bf6368acb1ab32588cf43ab3a4b1c301bf36328b1c8bd60"; \
            OPENCODE_ARCH="x64"; OPENCODE_SHA256="a0fa4b7b8bdacbd013e79a5f69d4220d36b545cd3ea296ba765f3016fa501b5b"; \
            STARSHIP_ARCH="x86_64"; STARSHIP_SHA256="b7c232b0e8249d8e55a40beb79c5c43a7d370f3f9408bd215deb0170daeaadf3"; \
            ZOXIDE_ARCH="x86_64"; ZOXIDE_SHA256="2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae" \
            ;; \
        arm64) \
            EZA_ARCH="aarch64"; EZA_SHA256="40b87ae8628aa2ff0f0d2dc24ab52f689631366385c3da630bae745671fd71ec"; \
            FZF_ARCH="arm64"; FZF_SHA256="f22204dd1a091d43e102268d062fd53b47133c8d8581671ee5eb225b75e31183"; \
            GH_ARCH="arm64"; GH_SHA256="06f86ec7103d41993b76cd78072f43595c34aaa56506d971d9860e67140bf909"; \
            OPENCODE_ARCH="arm64"; OPENCODE_SHA256="b16bd7593ea960a25d9c6849b3023bcd9b9244a6f51675341fd2052043b0670f"; \
            STARSHIP_ARCH="aarch64"; STARSHIP_SHA256="dc30189378d2f2e287384e8a692d3f95ad1df64cf0e8c36aa9201516028aed6b"; \
            ZOXIDE_ARCH="aarch64"; ZOXIDE_SHA256="f1f16c5d6298d63dee467eedea1cdcd8490e43e493bea43acd416dc9033ef641" \
            ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && EZA_ARCHIVE="eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" \
    && curl -fsSL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/${EZA_ARCHIVE}" -o "${EZA_ARCHIVE}" \
    && echo "${EZA_SHA256}  ${EZA_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${EZA_ARCHIVE}" -C /tmp/binaries/dev \
    && FZF_ARCHIVE="fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" \
    && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/${FZF_ARCHIVE}" -o "${FZF_ARCHIVE}" \
    && echo "${FZF_SHA256}  ${FZF_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${FZF_ARCHIVE}" -C /tmp/binaries/dev \
    && GH_ARCHIVE="gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${GH_ARCHIVE}" -o "${GH_ARCHIVE}" \
    && echo "${GH_SHA256}  ${GH_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${GH_ARCHIVE}" \
    && mv "gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /tmp/binaries/dev/gh \
    && OPENCODE_ARCHIVE="opencode-linux-${OPENCODE_ARCH}.tar.gz" \
    && curl -fsSL "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/${OPENCODE_ARCHIVE}" -o "${OPENCODE_ARCHIVE}" \
    && echo "${OPENCODE_SHA256}  ${OPENCODE_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${OPENCODE_ARCHIVE}" -C /tmp/binaries/dev \
    && STARSHIP_ARCHIVE="starship-${STARSHIP_ARCH}-unknown-linux-musl.tar.gz" \
    && curl -fsSL "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/${STARSHIP_ARCHIVE}" -o "${STARSHIP_ARCHIVE}" \
    && echo "${STARSHIP_SHA256}  ${STARSHIP_ARCHIVE}" | sha256sum -c - \
    && tar -xzf "${STARSHIP_ARCHIVE}" -C /tmp/binaries/dev \
    && ZOXIDE_ARCHIVE="zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" \
    && curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/${ZOXIDE_ARCHIVE}" -o "${ZOXIDE_ARCHIVE}" \
    && echo "${ZOXIDE_SHA256}  ${ZOXIDE_ARCHIVE}" | sha256sum -c - \
    && mkdir -p /tmp/zoxide \
    && tar -xzf "${ZOXIDE_ARCHIVE}" -C /tmp/zoxide \
    && mv /tmp/zoxide/zoxide /tmp/binaries/dev/zoxide \
    && chmod 755 /tmp/binaries/dev/* \
    && rm -rf ./*.tar.gz ./gh_* /tmp/zoxide

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BUILDER STAGE: Pin the shell framework without executing a remote installer
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS shell-builder

ARG ZINIT_COMMIT=429ab136312dfce68ad7d87a0ecb08c5063e7287
ARG OH_MY_ZSH_COMMIT=7ea697fd8138550ddf7262456d412f0dcd1cbf84

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --filter=blob:none https://github.com/zdharma-continuum/zinit.git /tmp/zinit \
    && git -C /tmp/zinit checkout "${ZINIT_COMMIT}" \
    && test "$(git -C /tmp/zinit rev-parse HEAD)" = "${ZINIT_COMMIT}" \
    && git clone --filter=blob:none https://github.com/ohmyzsh/ohmyzsh.git /tmp/oh-my-zsh \
    && git -C /tmp/oh-my-zsh checkout "${OH_MY_ZSH_COMMIT}" \
    && test "$(git -C /tmp/oh-my-zsh rev-parse HEAD)" = "${OH_MY_ZSH_COMMIT}"

FROM composer:2.10.2@sha256:5946476338742b200bb9ff88f8be56275ddae4b3949c72305cb0dbf10cfcb760 AS composer-builder

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

ENV TZ=UTC
ENV SERVER_NAME=:80
ENV DEBIAN_FRONTEND=noninteractive
ENV PNPM_HOME=/usr/local/share/pnpm
ENV PATH=$PNPM_HOME:$PATH
ENV pnpm_config_store_dir=/home/${USER}/.pnpm-store

# Install shared runtime packages and image tools from the target Debian suite
RUN apt-get update \
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
        pdo_sqlsrv-5.13.1 \
        sqlsrv-5.13.1 \
        sockets \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# Copy runtime configuration and verified artifacts after the expensive package layers
COPY ./.env /etc/profile.d/.env
COPY --chown=0:0 --chmod=755 ./usr/local/bin/* /usr/local/bin/
COPY --from=composer-builder --chown=0:0 --chmod=755 /usr/bin/composer /usr/bin/composer
COPY --from=binaries-builder --chown=0:0 /tmp/binaries/node /usr/local/node
COPY --from=binaries-builder --chown=0:0 /tmp/binaries/pnpm /usr/local/share/pnpm
COPY --from=binaries-builder --chown=0:0 /tmp/binaries/pnpm-global /usr/local/share/pnpm-global
COPY --from=binaries-builder --chown=0:0 /tmp/pnpm-store /usr/local/pnpm-store

# Add Node.js, pnpm, and global packages to PATH
ENV PATH=/usr/local/node/bin:/usr/local/share/pnpm:/usr/local/share/pnpm/bin:/usr/local/share/pnpm-global/bin:$PATH

# User creation and permissions
RUN groupadd --force -g "${WWWGROUP}" "${USER}" \
    && useradd -m --no-user-group -o -g "${WWWGROUP}" -u "${WWWUSER}" -s /bin/zsh "${USER}" \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && mkdir -p \
        "/home/${USER}/.config/psysh" \
        "/home/${USER}/.local/bin" \
        "/home/${USER}/.pnpm-store" \
        /app \
        /config/opencode \
        /data/opencode \
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

# Copy verified development binaries
COPY --from=dev-binaries-builder --chown=0:0 --chmod=755 /tmp/binaries/dev/* /usr/local/bin/

# Minimal development packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        htop \
        nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Development PHP extensions
RUN install-php-extensions xdebug

# Copy the pinned shell frameworks and development configuration
COPY --from=shell-builder --chown=${USER}:${USER} /tmp/zinit /home/${USER}/.data/zinit/zinit.git
COPY --from=shell-builder --chown=${USER}:${USER} /tmp/oh-my-zsh /home/${USER}/.oh-my-zsh
COPY --chown=${USER}:${USER} ./.zshrc /home/${USER}/.zshrc

# Switch to the runtime user and pre-download pinned shell plugins
USER ${USER}

ENV PATH=/home/${USER}/.local/bin:/home/${USER}/.opencode/bin:$PATH

RUN starship preset no-nerd-font -o "/home/${USER}/.config/starship.toml" \
    && zsh -i -c 'exit 0' \
    && test "$(git -C "/home/${USER}/.data/zinit/plugins/zsh-users---zsh-autosuggestions" rev-parse HEAD)" = "85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5" \
    && test "$(git -C "/home/${USER}/.data/zinit/plugins/Aloxaf---fzf-tab" rev-parse HEAD)" = "24105b15714bfec37989ed5c5b6e60f572253019" \
    && test "$(git -C "/home/${USER}/.data/zinit/plugins/zdharma-continuum---fast-syntax-highlighting" rev-parse HEAD)" = "3d574ccf48804b10dca52625df13da5edae7f553"

WORKDIR /app

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# PROD STAGE
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS prod

# Use production PHP configuration
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Copy production zshrc
COPY --chown=${USER}:${USER} ./.zshrc.prod /home/${USER}/.zshrc

# Copy the pinned shell frameworks
COPY --from=shell-builder --chown=${USER}:${USER} /tmp/zinit /home/${USER}/.data/zinit/zinit.git
COPY --from=shell-builder --chown=${USER}:${USER} /tmp/oh-my-zsh /home/${USER}/.oh-my-zsh

# Switch to the runtime user and pre-download pinned shell plugins
USER ${USER}

RUN zsh -i -c 'exit 0' \
    && test "$(git -C "/home/${USER}/.data/zinit/plugins/zsh-users---zsh-autosuggestions" rev-parse HEAD)" = "85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5" \
    && test "$(git -C "/home/${USER}/.data/zinit/plugins/zdharma-continuum---fast-syntax-highlighting" rev-parse HEAD)" = "3d574ccf48804b10dca52625df13da5edae7f553"

WORKDIR /app
