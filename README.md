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
- **Shell**: Zsh

### Dev Only

- **PHP**: Xdebug
- **Tools**: GitHub CLI, OpenCode, htop, nano, fzf, zoxide, eza
- **Shell**: Oh My Zsh, Starship prompt, syntax highlighting, autosuggestions, fzf-tab

## Available Tags

The entries below illustrate the configured PHP minor tag format:

| Tag | Description |
|-----|-------------|
| `php8.5` | PHP 8.5 production |
| `php8.5-dev` | PHP 8.5 development |
| `php8.4` | PHP 8.4 production |
| `php8.4-dev` | PHP 8.4 development |
| `latest` | Latest supported PHP production |
| `latest-dev` | Latest supported PHP development |

The workflow publishes the latest stable PHP patch in each configured minor line (8.4 and 8.5) and the latest stable FrankenPHP release. PHP and FrankenPHP are compiled from source; neither official image is used. Unqualified tags use Debian Trixie. For Debian Bookworm, insert `-bookworm` before the optional `-dev` suffix: `php8.5-bookworm`, `php8.5-bookworm-dev`, `latest-bookworm`, or `latest-bookworm-dev`. All images support `linux/amd64` and `linux/arm64`.

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

Docker Buildx and Python 3 are required. Resolve source releases once, then pass the
result to Bake. The resolver reads PHP's release metadata and SHA-256 checksums
from php.net and the stable FrankenPHP tag and commit from GitHub. Set
`GH_TOKEN` if GitHub's anonymous API rate limit is a problem.

```bash
sources="$(mktemp)"
docker buildx bake --print | python3 docker/resolve-sources.py > "$sources"

# Build and load one development image for the local platform
docker buildx bake -f docker-bake.hcl -f "$sources" runner-php-8-5-trixie-dev \
  --set 'runner-php-8-5-trixie-dev.platform=' --set 'runner-php-8-5-trixie-dev.tags=frankenphp:dev' --load

# Or build the whole default PHP, Debian, variant and platform matrix
docker buildx bake -f docker-bake.hcl -f "$sources"
rm "$sources"
```

To select minor lines, set `PHP_VERSION` (for example, `export PHP_VERSION=8.5`)
before both commands. Keep the resolved JSON if you need to retry the same
source revisions. The PHP build verifies the archive checksum and upstream
release signature before compiling the CLI and ZTS shared library. The
FrankenPHP build checks out the resolved commit and uses its Go module locks
and the same PHP library. Debian, Go, Node and Composer remain image
dependencies; the build still downloads extension and development tools.
If a later stable FrankenPHP release requires a newer Go major/minor,
update `GO_VERSION` at the top of the Dockerfile.

## Manually Rebuilding Published Images

After this workflow change is integrated into the default branch (`main`), open **Actions → build image → Run workflow**, select `main`, and run it. You can also use:

```bash
gh workflow run pipeline.yml --ref main
```

Manual runs refresh floating dependencies, build and test the full PHP/OS/variant/platform matrix, and publish the existing image tags after the tests pass. `pull = true` continues to fetch current base images. Manual runs selecting any other branch or tag are skipped to keep publication on `main`.

## Scheduled Builds

The daily build always rebuilds the development images. It rebuilds and republishes the production images only when something under them changed, so servers running them do not pull new layers for nothing:

- a new PHP patch or FrankenPHP source release, without waiting for upstream Docker images,
- a pending update for an installed Debian or PostgreSQL package (a refresh upgrades all installed system packages),
- a new Node 26, pnpm 11 or svgo release,
- and every Monday regardless, for updates such as Go, PHP extensions and Composer.

`.github/scripts/plan-scheduled-build.sh` makes that decision and writes its reasons to the run's summary. If it cannot decide, every image is rebuilt.

## Configuration

The container runs as user `deploy` (UID 1000). Key paths:

- **App**: `/app`
- **pnpm store**: `/home/deploy/.pnpm-store`
- **Caddy data**: `/data/caddy`
- **Caddy config**: `/config/caddy`

Environment variables:

- `SERVER_NAME=:80` - Caddy server name
- `TZ=UTC` - Timezone

### Production PHP Settings

The production images add `conf.d/10-production.ini`. Each setting reads an environment variable, so an app changes it on its container instead of shipping an ini file:

| Variable | Default | Setting |
|----------|---------|---------|
| `PHP_OPCACHE_ENABLE` | `1` | `opcache.enable` |
| `PHP_OPCACHE_MEMORY_CONSUMPTION` | `256` | `opcache.memory_consumption` (MB) |
| `PHP_OPCACHE_INTERNED_STRINGS_BUFFER` | `32` | `opcache.interned_strings_buffer` (MB) |
| `PHP_OPCACHE_MAX_ACCELERATED_FILES` | `32531` | `opcache.max_accelerated_files` |
| `PHP_OPCACHE_VALIDATE_TIMESTAMPS` | `0` | `opcache.validate_timestamps` |
| `PHP_OPCACHE_REVALIDATE_FREQ` | `2` | `opcache.revalidate_freq` (only with timestamps on) |
| `PHP_REALPATH_CACHE_SIZE` | `4096K` | `realpath_cache_size` |
| `PHP_REALPATH_CACHE_TTL` | `600` | `realpath_cache_ttl` (seconds) |
| `PHP_SESSION_UPLOAD_PROGRESS_ENABLED` | `0` | `session.upload_progress.enabled` |

`expose_php` is always `Off`. With `PHP_OPCACHE_VALIDATE_TIMESTAMPS=0`, PHP never notices a changed PHP file: deploy a new container rather than editing files in a running one, and set it to `1` where code is mounted from the host. The file leaves memory, upload, post and execution-time limits alone, because PHP reads `conf.d` after `php.ini` and would override what apps set in their own `php.ini`.

## License

[MIT](LICENSE)
