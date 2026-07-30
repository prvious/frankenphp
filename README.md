# FrankenPHP Docker Images

Custom [FrankenPHP](https://frankenphp.dev) Docker images with batteries included for Laravel development and production.

## Quick Start

```bash
# Development (includes xdebug, dev tools)
docker pull ghcr.io/prvious/frankenphp:php8.4-dev

# Production
docker pull ghcr.io/prvious/frankenphp:php8.4
```

## What's Included

### Base (both dev & prod)
- **PHP Extensions**: mysqli, pdo_mysql, pgsql, pdo_pgsql, bcmath, gd, imagick, imap, pcntl, zip, intl, exif, xml, sqlsrv, pdo_sqlsrv, sockets
- **Node.js**: v26
- **Package Managers**: Composer, pnpm v11
- **Database Clients**: PostgreSQL 17, MySQL
- **Image Tools**: jpegoptim, optipng, pngquant, gifsicle, avifenc, svgo, ffmpeg
- **Process Manager**: Supervisor
- **Shell**: Zsh with zinit

### Dev Only
- **PHP**: Xdebug
- **Tools**: GitHub CLI, htop, nano, fzf, zoxide, eza
- **Shell**: Starship prompt, syntax highlighting, autosuggestions, fzf-tab

## Available Tags

| Tag | Description |
|-----|-------------|
| `php8.4` | PHP 8.4 production |
| `php8.4-dev` | PHP 8.4 development |
| `php8.3` | PHP 8.3 production |
| `php8.3-dev` | PHP 8.3 development |
| `latest` | Latest PHP production |
| `latest-dev` | Latest PHP development |

All images are multi-arch: `linux/amd64` and `linux/arm64`.

## Usage with Laravel

```yaml
# docker-compose.yml
services:
  app:
    image: ghcr.io/prvious/frankenphp:php8.4-dev
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
docker build --build-arg VERSION=8.4 --target dev -t frankenphp:dev .

# Build prod image
docker build --build-arg VERSION=8.4 --target prod -t frankenphp:prod .

# Build all variants with bake
docker buildx bake
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

MIT
