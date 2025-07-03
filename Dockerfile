ARG VERSION
FROM dunglas/frankenphp:php${VERSION} AS runner

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
    && apt install -y supervisor git unzip default-mysql-client \
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
    && install-php-extensions @composer mysqli pdo_mysql bcmath gd imap pcntl zip intl exif ftp xml pdo_sqlsrv sqlsrv \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && cp "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini" \
    && groupadd --force -g $WWWGROUP ${USER} \
    && useradd -m --no-user-group -o -g $WWWGROUP -u ${WWWUSER} -s /bin/bash ${USER} \
    && setcap CAP_NET_BIND_SERVICE=+eip /usr/local/bin/frankenphp \
    && chown -R ${USER}:${USER} /data/caddy && chown -R ${USER}:${USER} /config/caddy && chown -R ${USER}:${USER} /app

WORKDIR /app
USER ${USER}
