ARG TAG
FROM dunglas/frankenphp:${TAG} AS runner

SHELL [ "/bin/bash", "-l", "-exo", "pipefail", "-c" ]
RUN sed -i 's#/bin/sh#/bin/bash#g' /etc/passwd

LABEL maintainer="Clovis Muneza"
LABEL org.opencontainers.image.source="https://github.com/prvious/frankenphp"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV SERVER_NAME=:80
ENV FNM_DIR=/usr/local/fnm
ENV TZ=UTC
ENV PATH=${FNM_DIR}/aliases/default/bin:$PATH

COPY ./custom.sh /etc/profile.d/custom.sh

RUN apt update \
    && apt install -y supervisor git curl unzip ca-certificates \
    && mkdir -p "${FNM_DIR}" \
    && curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "${FNM_DIR}" --skip-shell \
    && ln -s ${FNM_DIR}/fnm /usr/bin/ && chmod +x /usr/bin/fnm \
    && fnm -V \
    && fnm install --latest \
    && echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> /etc/profile.d/fnm.sh \
    && echo 'source /etc/profile.d/custom.sh' >> /etc/bash.bashrc \
    && eval "$(fnm env --use-on-cd --shell bash)" \
    && fnm use latest --install-if-missing \
    && npm install -g npm pnpm \
    && install-php-extensions @composer bcmath gd imap pcntl zip intl exif ftp xml \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && cp "${PHP_INI_DIR}/php.ini-development" "${PHP_INI_DIR}/php.ini" \
    && chsh -s /bin/bash root