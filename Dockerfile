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
ENV FNM_DIR=/usr/local/fnm
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=${FNM_DIR}/aliases/default/bin:$PATH

COPY ./env.sh /etc/profile.d/env.sh

RUN apt update \
    && apt-get install -y gnupg lsb-release \
    && echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/pgdg.gpg \
    && apt-get update \
    && apt-get install -y  supervisor git unzip postgresql-client-17 default-mysql-client zsh \
    && sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    && mkdir -p "${FNM_DIR}" \
    && curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "${FNM_DIR}" --skip-shell \
    && ln -s ${FNM_DIR}/fnm /usr/bin/ && chmod +x /usr/bin/fnm \
    && fnm -V \
    && fnm install --latest \
    && echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> /etc/profile.d/fnm.sh \
    && echo 'source /etc/profile.d/env.sh' >> /etc/bash.bashrc \
    && eval "$(fnm env --use-on-cd --shell bash)" \
    && fnm use latest --install-if-missing \
    && npm install -g npm pnpm \
    && apt install -y jpegoptim optipng pngquant gifsicle libavif-bin ffmpeg \
    && npm install -g npm pnpm svgo \
    && install-php-extensions @composer mysqli pdo_mysql pgsql pdo_pgsql bcmath gd imagick imap pcntl zip intl exif ftp xml pdo_sqlsrv sqlsrv sockets \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini" \
    && groupadd --force -g $WWWGROUP ${USER} \
    && useradd -m --no-user-group -o -g $WWWGROUP -u ${WWWUSER} -s /bin/zsh ${USER} \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
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
    && apt-get install -y htop nano gh \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /app
USER ${USER}


#---------------------------------------------------------------------------------------------------------------------------------------------------------------------------
    
FROM base AS prod

WORKDIR /app
USER ${USER}