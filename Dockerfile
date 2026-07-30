ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS frankenphp-base

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BUILDER STAGE: Download static binaries and tools
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS binaries-builder

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    jq \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/binaries

# Download minimal Node.js binary (just node, no npm)
RUN NODE_VERSION=26 \
    && if [ "$TARGETARCH" = "amd64" ]; then NODE_ARCH="x64"; else NODE_ARCH="arm64"; fi \
    && LATEST_NODE=$(curl -s https://nodejs.org/dist/latest-v${NODE_VERSION}.x/ | grep -oP "node-v${NODE_VERSION}\.\d+\.\d+" | head -1) \
    && curl -sL "https://nodejs.org/dist/latest-v${NODE_VERSION}.x/${LATEST_NODE}-linux-${NODE_ARCH}.tar.gz" | tar -xz \
    && mkdir -p /tmp/binaries/node/bin \
    && mv ${LATEST_NODE}-linux-${NODE_ARCH}/bin/node /tmp/binaries/node/bin/ \
    && rm -rf ${LATEST_NODE}-linux-${NODE_ARCH}

# Download the latest pnpm 11 release
RUN PNPM_VERSION=$(curl -fsSL https://registry.npmjs.org/@pnpm/exe | jq -r '.["dist-tags"]["latest-11"]') \
    && test -n "${PNPM_VERSION}" \
    && test "${PNPM_VERSION}" != "null" \
    && curl -fsSL https://get.pnpm.io/install.sh | env PNPM_VERSION="${PNPM_VERSION}" PNPM_HOME=/tmp/binaries/pnpm bash -

# Install svgo using pnpm in builder
RUN export PATH="/tmp/binaries/node/bin:/tmp/binaries/pnpm:$PATH" \
    && export PNPM_HOME=/tmp/binaries/pnpm \
    && mkdir -p /tmp/binaries/pnpm-global \
    && pnpm config set store-dir /tmp/pnpm-store --global \
    && pnpm config set global-dir /tmp/binaries/pnpm-global --global \
    && pnpm add -g svgo \
    && rm -rf /tmp/pnpm-store

# Download development-only binaries
FROM binaries-builder AS dev-binaries-builder

# Download GitHub CLI
RUN GH_VERSION=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && if [ "$TARGETARCH" = "amd64" ]; then ARCH="amd64"; else ARCH="arm64"; fi \
    && curl -sL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.tar.gz" -o gh.tar.gz \
    && tar -xzf gh.tar.gz \
    && mv gh_${GH_VERSION}_linux_${ARCH}/bin/gh gh \
    && rm -rf gh*.tar.gz gh_*

# Download eza
RUN EZA_VERSION=$(curl -s https://api.github.com/repos/eza-community/eza/releases/latest | jq -r .tag_name | sed 's/^v//') \
    && if [ "$TARGETARCH" = "amd64" ]; then EZA_ARCH="x86_64"; else EZA_ARCH="aarch64"; fi \
    && curl -sL "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" | tar -xz

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# BUILDER STAGE: Image optimization tools
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM debian:bookworm-slim AS tools-builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    jpegoptim \
    optipng \
    pngquant \
    gifsicle \
    libavif-bin \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Copy binaries to a clean location
RUN mkdir -p /tmp/tools \
    && cp /usr/bin/jpegoptim /tmp/tools/ \
    && cp /usr/bin/optipng /tmp/tools/ \
    && cp /usr/bin/pngquant /tmp/tools/ \
    && cp /usr/bin/gifsicle /tmp/tools/ \
    && cp /usr/bin/avifenc /tmp/tools/ \
    && cp /usr/bin/ffmpeg /tmp/tools/

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
ENV PNPM_STORE_DIR=/home/${USER}/.pnpm-store

COPY ./.env /etc/profile.d/.env
COPY --chmod=755 ./usr/local/bin/* /usr/local/bin/

# Copy composer from official image
COPY --from=composer:2 --chmod=755 /usr/bin/composer /usr/bin/composer

# Copy Node.js (just the binary) and pnpm from builder
COPY --from=binaries-builder /tmp/binaries/node /usr/local/node
COPY --from=binaries-builder /tmp/binaries/pnpm /usr/local/share/pnpm
COPY --from=binaries-builder /tmp/binaries/pnpm-global /usr/local/share/pnpm-global

# Copy image optimization tools from builder
COPY --from=tools-builder --chmod=755 /tmp/tools/* /usr/local/bin/

# Add Node.js, pnpm, and global packages to PATH
ENV PATH=/usr/local/node/bin:/usr/local/share/pnpm:/usr/local/share/pnpm-global/bin:$PATH

# Minimal system packages (no Node, no image tools, no gh/eza)
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gnupg \
        lsb-release \
        ca-certificates \
        supervisor \
        git \
        unzip \
        zsh \
        procps \
        # Required runtime libs for image tools
        libjpeg62-turbo \
        libpng16-16 \
        libavif15 \
        libavcodec59 \
        libavformat59 \
        libavutil57 \
        libswscale6 \
        libswresample4 \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/pgdg.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-17 \
        default-mysql-client \
    && echo 'source /etc/profile.d/.env' >> /etc/bash.bashrc \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Configure pnpm store directory
RUN export PATH="/usr/local/node/bin:/usr/local/share/pnpm:$PATH" \
    && pnpm config set store-dir /home/${USER}/.pnpm-store --global

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
        sockets \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

# User creation and permissions
RUN groupadd --force -g ${WWWGROUP} ${USER} \
    && useradd -m --no-user-group -o -g ${WWWGROUP} -u ${WWWUSER} -s /bin/zsh ${USER} \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && mkdir -p /home/${USER}/.local/bin \
    && chown -R ${USER}:${USER} /home/${USER} /data/caddy /config/caddy

# Final cleanup - remove unnecessary files
RUN rm -rf \
        /usr/share/doc/* \
        /usr/share/man/* \
        /usr/share/locale/* \
        /var/cache/apt/* \
        /var/lib/apt/lists/* \
        /tmp/* \
        /var/tmp/* \
        /root/.cache \
        /root/.npm

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# DEV STAGE
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS dev

# Copy development binaries
COPY --from=dev-binaries-builder --chmod=755 /tmp/binaries/gh /usr/local/bin/gh
COPY --from=dev-binaries-builder --chmod=755 /tmp/binaries/eza /usr/local/bin/eza

# Minimal development packages
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        htop \
        nano \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Development PHP extensions
RUN install-php-extensions xdebug

# Switch to deploy user for user-level installations
USER ${USER}

# Install starship and opencode
RUN curl -sS https://starship.rs/install.sh | sh -s -- --yes --bin-dir=/home/${USER}/.local/bin \
    && curl -fsSL https://opencode.ai/install | bash

# Copy zshrc and create user directories
COPY --chown=${USER}:${USER} ./.zshrc /home/${USER}/.zshrc

# Install zinit, fzf, zoxide, and configure starship
RUN ZINIT_HOME="/home/${USER}/.local/share/zinit" NO_EDIT=1 NO_TUTORIAL=1 \
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" \
    && git clone --depth 1 https://github.com/junegunn/fzf.git /home/${USER}/.fzf \
    && /home/${USER}/.fzf/install --all --no-update-rc \
    && curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
    && mkdir -p /home/${USER}/.config \
    && starship preset no-nerd-font -o /home/${USER}/.config/starship.toml \
    && zsh -i -c 'zinit self-update && exit 0' || true

ENV PATH=/home/deploy/.local/bin:/home/deploy/.fzf/bin:$PATH

WORKDIR /app

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
# PROD STAGE
#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS prod

# Use production PHP configuration
RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Copy production zshrc
COPY --chown=${USER}:${USER} ./.zshrc.prod /home/${USER}/.zshrc

# Create user directories before switching user
RUN mkdir -p /home/${USER}/.local/share \
    && chown -R ${USER}:${USER} /home/${USER}

# Switch to deploy user for user-level installations
USER ${USER}

# Install zinit and pre-download plugins
RUN ZINIT_HOME="/home/${USER}/.local/share/zinit" NO_EDIT=1 NO_TUTORIAL=1 \
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" \
    && zsh -i -c 'zinit self-update && exit 0' || true

WORKDIR /app
