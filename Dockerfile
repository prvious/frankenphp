ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS base

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
COPY ./usr/local/bin/* /usr/local/bin/

RUN apt update \
    && apt-get install -y gnupg lsb-release ca-certificates curl \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/pgdg.gpg \
    && apt-get update \
    && apt-get install -y supervisor git unzip postgresql-client-17 default-mysql-client zsh procps \
    && echo 'source /etc/profile.d/.env' >> /etc/bash.bashrc \
    && curl -fsSL https://get.pnpm.io/install.sh | env PNPM_HOME="${PNPM_HOME}" bash - \
    && export PATH="${PNPM_HOME}:${PATH}" \
    && pnpm config set store-dir /home/${USER}/.pnpm-store --global \
    && pnpm env use --global 24 \
    && npm install -g npm \
    && apt install -y jpegoptim optipng pngquant gifsicle libavif-bin ffmpeg \
    && pnpm add -g svgo \
    && install-php-extensions @composer mysqli pdo_mysql pgsql pdo_pgsql bcmath gd imagick imap pcntl zip intl exif ftp xml pdo_sqlsrv sqlsrv sockets \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini" \
    && groupadd --force -g $WWWGROUP ${USER} \
    && useradd -m --no-user-group -o -g $WWWGROUP -u ${WWWUSER} -s /bin/zsh ${USER} \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chmod +x /usr/local/bin/* \
    && chown -R ${USER}:${USER} /data/caddy && chown -R ${USER}:${USER} /config/caddy && chown -R ${USER}:${USER} /app \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------

FROM base AS dev

RUN apt-get update \
    && install-php-extensions xdebug \
    && (type -p wget >/dev/null || (apt update && apt install wget -y)) \
	&& mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y htop nano gh zsh \
    && curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    && mkdir -p /etc/apt/keyrings \
    && wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list \
    && chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list \
    && apt update \
    && apt install -y eza \
    && pnpm add -g opencode-ai \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy zshrc first so we can pre-download plugins
COPY --chown=${USER}:${USER} ./.zshrc /home/${USER}/.zshrc

# Create directories for user tools
RUN mkdir -p /home/${USER}/.local/share /home/${USER}/.config /home/${USER}/.fzf \
    && chown -R ${USER}:${USER} /home/${USER}

# Switch to the deploy user to install zinit and tools
USER ${USER}

# Install zinit, fzf, zoxide, starship preset, and pre-download all zinit plugins
RUN ZINIT_HOME="/home/${USER}/.local/share/zinit" NO_EDIT=1 NO_TUTORIAL=1 \
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" \
    && git clone --depth 1 https://github.com/junegunn/fzf.git /home/${USER}/.fzf \
    && /home/${USER}/.fzf/install --all --no-update-rc \
    && curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash \
    && mkdir -p /home/${USER}/.config \
    && starship preset no-nerd-font -o /home/${USER}/.config/starship.toml \
    && zsh -i -c 'zinit self-update && exit 0' || true

# Add user bin directories to PATH for fzf and zoxide
ENV PATH=/home/deploy/.local/bin:/home/deploy/.fzf/bin:$PATH

WORKDIR /app


#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    
FROM base AS prod

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Copy zshrc first so we can pre-download plugins
COPY --chown=${USER}:${USER} ./.zshrc.prod /home/${USER}/.zshrc

# Switch to the deploy user to install zinit and pre-download plugins
USER ${USER}

# Install zinit and pre-download plugins
RUN ZINIT_HOME="/home/${USER}/.local/share/zinit" NO_EDIT=1 NO_TUTORIAL=1 \
    bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" \
    && zsh -i -c 'zinit self-update && exit 0' || true

WORKDIR /app