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
    && curl --retry 5 --retry-delay 5 -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir "${FNM_DIR}" --skip-shell \
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
    && apt-get install -y htop nano gh zsh-autosuggestions zsh-syntax-highlighting zsh fontconfig \
    && curl -sS https://starship.rs/install.sh | sh -s -- --yes \
    &&  mkdir -p /etc/apt/keyrings \
    && wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | gpg --dearmor -o /etc/apt/keyrings/gierens.gpg \
    && echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | tee /etc/apt/sources.list.d/gierens.list \
    && chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list \
    && apt update \
    && apt install -y eza \
    && curl --retry 5 --retry-delay 5 -fsSL https://opencode.ai/install | bash \
    && mkdir -p /usr/share/fonts/nerd-fonts \
    && wget -q https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -O /tmp/JetBrainsMono.zip \
    && unzip /tmp/JetBrainsMono.zip -d /usr/share/fonts/nerd-fonts/JetBrainsMono \
    && rm /tmp/JetBrainsMono.zip \
    && fc-cache -fv \
    && eval "$(fnm env --use-on-cd --shell bash)" \
    && source /etc/profile.d/env.sh \
    && pnpm install -g playwright \
    && pnpx playwright install --with-deps \
    && apt-get -y autoremove \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

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