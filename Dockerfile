FROM dunglas/dunglas/frankenphp

SHELL [ "/bin/bash", "-l", "-euxo", "pipefail", "-c" ]

LABEL maintainer="Clovis Muneza"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC
ENV SERVER_NAME=:80
ENV FNM_DIR=/usr/local/fnm
ENV TZ=UTC
ENV PATH=${FNM_DIR}/aliases/default/bin:$PATH

RUN apt update \
    && apt install -y supervisor git curl unzip ca-certificates \
    && mkdir -p "${FNM_DIR}" \
    && curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "${FNM_DIR}" --skip-shell \
    && ln -s ${FNM_DIR}/fnm /usr/bin/ && chmod +x /usr/bin/fnm \
    && fnm -V \
    && fnm install --lts \
    && echo 'eval "$(fnm env --use-on-cd --shell bash)"' >> /etc/bash.bashrc \
    && source /etc/bash.bashrc \
    && fnm alias default lts \
    && fnm use default \
    && npm install -g npm pnpm \
    && install-php-extensions @composer bcmath gd imap pcntl zip intl exif ftp xml \
    && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone \
    && apt-get remove -y curl gnupg2 \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    && cp "${PHP_INI_DIR}/php.ini-development" "${PHP_INI_DIR}/php.ini"