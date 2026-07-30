# FrankenPHP Docker Images

Custom [FrankenPHP](https://frankenphp.dev) Docker images with batteries included for Laravel development and production.

## Quick Start

```bash
# Development (includes xdebug, dev tools)
docker pull ghcr.io/prvious/frankenphp:php8.5-dev

# Production
docker pull ghcr.io/prvious/frankenphp:php8.5
```

## What's Included

### Base (both dev & prod)

- **PHP Extensions**: mysqli, pdo_mysql, pgsql, pdo_pgsql, bcmath, gd, imagick, imap, pcntl, zip, intl, exif, ftp, xml, sqlsrv, pdo_sqlsrv, sockets
- **Node.js**: v26
- **Package Managers**: Composer, pnpm v11
- **Database Clients**: PostgreSQL 17, MySQL
- **Image Tools**: jpegoptim, optipng, pngquant, gifsicle, avifenc, svgo, ffmpeg
- **Process Manager**: Supervisor
- **Shell**: Zsh with zinit

### Dev Only

- **PHP**: Xdebug
- **Tools**: GitHub CLI, OpenCode, htop, nano, fzf, zoxide, eza
- **Shell**: Starship prompt, syntax highlighting, autosuggestions, fzf-tab

## Available Tags

The entries below illustrate the dynamically selected PHP minor tag format:

| Tag | Description |
|-----|-------------|
| `php8.5` | PHP 8.5 production |
| `php8.5-dev` | PHP 8.5 development |
| `php8.4` | PHP 8.4 production |
| `php8.4-dev` | PHP 8.4 development |
| `latest` | Latest supported PHP production |
| `latest-dev` | Latest supported PHP development |

The workflow discovers and publishes the two newest stable PHP minor lines. Unqualified tags use Debian Trixie. For Debian Bookworm, insert `-bookworm` before the optional `-dev` suffix: `php8.5-bookworm`, `php8.5-bookworm-dev`, `latest-bookworm`, or `latest-bookworm-dev`. All images support `linux/amd64` and `linux/arm64`.

## Usage with Laravel

```yaml
# docker-compose.yml
services:
  app:
    image: ghcr.io/prvious/frankenphp:php8.5-dev
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - .:/app
    working_dir: /app
```

### Laravel Aliases

These aliases are available inside the container:

```bash
pa        # php artisan
pint      # ./vendor/bin/pint
pest      # ./vendor/bin/pest
stan      # ./vendor/bin/phpstan
amf       # php artisan migrate:fresh
amfs      # php artisan migrate:fresh --seed
```

### Health Checks

Built-in health check scripts for Laravel services:

```bash
healthcheck-horizon   # Check Laravel Horizon
healthcheck-octane    # Check Laravel Octane
healthcheck-queue     # Check queue workers
healthcheck-schedule  # Check scheduler
```

## Building Locally

```bash
# Build dev image
docker build --build-arg VERSION=8.5-trixie --target dev -t frankenphp:dev .

# Build prod image
docker build --build-arg VERSION=8.5-trixie --target prod -t frankenphp:prod .

# Build the default PHP 8.4/8.5 matrix
docker buildx bake

# Build an explicit version set and label it with the current commit
PHP_VERSION=8.4.23,8.5.8 SHA="$(git rev-parse HEAD)" LATEST=8.5.8 docker buildx bake
```

## Configuration

The container runs as user `deploy` (UID 1000). Key paths:

- **App**: `/app`
- **pnpm store**: `/home/deploy/.pnpm-store`
- **Caddy data**: `/data/caddy`
- **Caddy config**: `/config/caddy`

Environment variables:

- `SERVER_NAME=:80` - Caddy server name
- `TZ=UTC` - Timezone

## License

[MIT](LICENSE)
