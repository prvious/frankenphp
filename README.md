# FrankenPHP Docker Images

Production-ready and development-optimized Docker images built on top of FrankenPHP, engineered for modern PHP applications with comprehensive tooling, multi-architecture support, and performance-focused configuration.

## Overview

This repository provides custom FrankenPHP Docker images with batteries included for PHP development and deployment. Built on the official FrankenPHP base images, these containers come pre-configured with essential PHP extensions, database clients, Node.js tooling, image optimization utilities, and developer productivity tools.

FrankenPHP combines the power of Caddy web server with PHP, offering HTTP/3, automatic HTTPS, and native PHP execution in a single binary. These images extend that foundation with everything you need for Laravel, Symfony, and modern PHP applications.

## Key Features

### Production-Ready
- **Multi-Architecture Support**: Native builds for AMD64 and ARM64 architectures
- **Optimized PHP Configuration**: Production-tuned PHP settings out of the box
- **Comprehensive Extensions**: Database drivers (MySQL, PostgreSQL, SQL Server), image processing, caching, and more
- **Zero Downtime**: Built-in health check utilities for load balancers and orchestration platforms
- **Minimal Attack Surface**: Production images exclude development tools and debugging extensions

### Development-Optimized
- **Xdebug Integration**: Pre-configured for step debugging and profiling
- **Enhanced Shell Experience**: Zsh with Zinit, Starship prompt, and intelligent completions
- **Modern CLI Tools**: GitHub CLI, eza, fzf, zoxide, htop for enhanced productivity
- **Fast Package Management**: pnpm with optimized store configuration
- **Interactive Development**: Pre-installed development utilities and code quality tools

### Full-Stack Capabilities
- **Node.js Ecosystem**: Node 24 with npm and pnpm for modern frontend development
- **Image Optimization**: jpegoptim, optipng, pngquant, gifsicle, AVIF support, and FFmpeg
- **Database Clients**: PostgreSQL 17 and MySQL clients for direct database access
- **Supervisor Integration**: Process management for running multiple services
- **Laravel-Optimized**: Built-in aliases and tools for Laravel development workflows

## Available Images

All images are available on GitHub Container Registry and support both `linux/amd64` and `linux/arm64` platforms.

### Production Images
```
ghcr.io/prvious/frankenphp:latest          # Latest PHP 8.4 (Bookworm)
ghcr.io/prvious/frankenphp:php8.4          # PHP 8.4 (Bookworm)
ghcr.io/prvious/frankenphp:php8.3          # PHP 8.3 (Bookworm)
ghcr.io/prvious/frankenphp:php8.4.2        # Specific PHP version
```

### Development Images
```
ghcr.io/prvious/frankenphp:latest-dev      # Latest PHP 8.4 with dev tools
ghcr.io/prvious/frankenphp:php8.4-dev      # PHP 8.4 with dev tools
ghcr.io/prvious/frankenphp:php8.3-dev      # PHP 8.3 with dev tools
ghcr.io/prvious/frankenphp:php8.4.2-dev    # Specific PHP version with dev tools
```

## Quick Start

### Production Deployment

```dockerfile
FROM ghcr.io/prvious/frankenphp:php8.4

COPY . /app

RUN composer install --no-dev --optimize-autoloader \
    && pnpm install --prod \
    && pnpm run build

EXPOSE 80
EXPOSE 443

CMD ["frankenphp", "run"]
```

### Local Development

```bash
# Pull the latest development image
docker pull ghcr.io/prvious/frankenphp:php8.4-dev

# Run interactively with your project mounted
docker run -it --rm \
  -v $(pwd):/app \
  -p 80:80 \
  ghcr.io/prvious/frankenphp:php8.4-dev \
  bash

# Or use with Docker Compose
docker-compose up
```

### Docker Compose Example

```yaml
version: '3.8'

services:
  app:
    image: ghcr.io/prvious/frankenphp:php8.4-dev
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - .:/app
    environment:
      SERVER_NAME: :80
      XDEBUG_MODE: debug
      XDEBUG_CONFIG: client_host=host.docker.internal
    networks:
      - app-network

  database:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - app-network

networks:
  app-network:
    driver: bridge

volumes:
  postgres-data:
```

## Installed Extensions

### PHP Extensions (All Images)
- **Database**: mysqli, pdo_mysql, pgsql, pdo_pgsql, pdo_sqlsrv, sqlsrv
- **Image Processing**: gd, imagick, exif
- **Core Functionality**: bcmath, intl, zip, xml, sockets
- **Mail & FTP**: imap, ftp
- **Background Processing**: pcntl

### Additional Extensions (Development Only)
- **Debugging**: xdebug (pre-configured for remote debugging)

## Included Tools & Utilities

### Package Managers & Runtimes
- **PHP**: Composer 2.x
- **Node.js**: Version 24 (managed via pnpm env)
- **pnpm**: Fast, disk space efficient package manager
- **npm**: Latest stable version

### Database Clients
- **PostgreSQL**: psql client (version 17)
- **MySQL**: mysql client (latest)

### Image Optimization Suite
- **JPEG**: jpegoptim
- **PNG**: optipng, pngquant
- **GIF**: gifsicle
- **AVIF**: libavif-bin (avifenc)
- **SVG**: svgo (via npm global)
- **Video**: FFmpeg

### Development Tools (Dev Images Only)
- **Version Control**: GitHub CLI (gh)
- **File Navigation**: eza (modern ls replacement), fzf (fuzzy finder), zoxide (smart cd)
- **System Monitoring**: htop
- **Text Editing**: nano
- **Shell Enhancement**: Zsh with Zinit, Starship prompt
- **AI Assistance**: opencode-ai

### Laravel Development Aliases

Pre-configured shell aliases for Laravel workflows:

```bash
pint          # ./vendor/bin/pint (Laravel Pint formatter)
pa            # php artisan
stan          # ./vendor/bin/phpstan (static analysis)
phpstan       # ./vendor/bin/phpstan
pest          # ./vendor/bin/pest (testing framework)
amf           # php artisan migrate:fresh
amfs          # php artisan migrate:fresh --seed
```

### Health Check Utilities

Built-in health check scripts for container orchestration:

- `healthcheck-octane`: Laravel Octane health verification
- `healthcheck-horizon`: Laravel Horizon queue monitor
- `healthcheck-queue`: Queue worker health check
- `healthcheck-schedule`: Scheduler health verification

## Building Images Locally

### Prerequisites
- Docker with BuildKit enabled
- Docker Buildx plugin
- Multi-architecture support (for ARM64 builds)

### Build Commands

```bash
# Build all variants (production and development for all PHP versions)
docker buildx bake

# Build specific variant
docker buildx bake runner-php-8-4-bookworm-dev
docker buildx bake runner-php-8-3-bookworm-production

# Build and push to registry
docker buildx bake --push

# Preview build configuration
docker buildx bake --print
```

### Build Matrix

The build system supports:
- **PHP Versions**: 8.3, 8.4 (automatically tracks latest patch versions)
- **OS Variants**: Bookworm (Debian 12)
- **Build Types**: Production and Development
- **Architectures**: linux/amd64, linux/arm64

## Configuration

### Environment Variables

```bash
# Server configuration
SERVER_NAME=:80              # FrankenPHP server name
TZ=UTC                       # Timezone

# Development settings (dev images)
XDEBUG_MODE=debug            # Xdebug mode: debug, coverage, profile
XDEBUG_CONFIG=...            # Xdebug configuration

# pnpm configuration
PNPM_HOME=/usr/local/share/pnpm
PNPM_STORE_DIR=/home/deploy/.pnpm-store
```

### User Configuration

Images run as user `deploy` (UID: 1000, GID: 1000) by default, matching common development environment user IDs.

Build-time arguments:
```dockerfile
ARG WWWUSER=1000
ARG WWWGROUP=1000
ARG USER=deploy
```

### PHP Configuration

- **Production**: Uses php.ini-production settings
- **Development**: Uses php.ini-development settings with Xdebug enabled

## Testing

Validate installed extensions and tools:

```bash
# Test production image
docker run --rm ghcr.io/prvious/frankenphp:php8.4 php test.php production

# Test development image
docker run --rm ghcr.io/prvious/frankenphp:php8.4-dev php test.php dev
```

The test script verifies:
- All required PHP extensions are loaded
- Expected CLI tools and binaries are available
- Configuration is correct for the environment
- Package manager configurations are properly set

## Architecture

### Multi-Stage Build

The Dockerfile uses a multi-stage build pattern:

1. **Base Stage**: Common setup for both production and development
   - System packages installation
   - PHP extensions compilation
   - User and permission configuration
   - Core tooling setup

2. **Production Stage**: Optimized for deployment
   - PHP production configuration
   - Minimal Zsh setup
   - No development tools
   - Smaller image size

3. **Development Stage**: Enhanced for local development
   - Xdebug extension
   - Full Zsh configuration with plugins
   - Development CLI tools
   - GitHub CLI integration

### Build Automation

Automated builds run daily via GitHub Actions:
- Checks for new PHP releases
- Builds images for latest patch versions of supported minor versions
- Pushes to GitHub Container Registry
- Supports manual triggering for specific versions

## Security

### Capabilities

FrankenPHP binary has `CAP_NET_BIND_SERVICE` capability, allowing it to bind to privileged ports (80, 443) without running as root.

### User Permissions

All processes run as non-root user `deploy` with appropriate permissions for:
- Application directory `/app`
- Caddy data directory `/data/caddy`
- Caddy configuration directory `/config/caddy`

### Minimal Surface Area

Production images exclude:
- Development tools (gh, htop, nano)
- Debugging extensions (xdebug)
- Interactive shell enhancements
- Unnecessary system utilities

## Performance Optimization

### pnpm Store

Configured with a dedicated store directory for optimal package sharing:
```bash
/home/deploy/.pnpm-store
```

### Image Layers

Optimized layer caching strategy:
- Environment files copied early
- System packages installed in batched commands
- Plugin pre-downloading during build time
- Cleanup of apt caches and temporary files

### Multi-Architecture

Native builds for ARM64 provide optimal performance on:
- Apple Silicon (M1, M2, M3 Macs)
- AWS Graviton instances
- Raspberry Pi 4+
- Other ARM-based servers

## Contributing

Contributions are welcome! Please follow these guidelines:

### Code Style
- **HCL**: 4-space indentation, descriptive variable names
- **Shell**: Use `set -exo pipefail`, proper quoting
- **Docker**: Multi-platform support, proper OCI labels
- **Documentation**: Clear, professional, no emojis

### Pull Request Process
1. Fork the repository
2. Create a feature branch
3. Test changes with `docker buildx bake`
4. Validate with test suite
5. Submit PR with clear description

## License

This project builds upon FrankenPHP and includes various open-source tools. Please refer to individual component licenses for specific terms.

## Related Projects

- [FrankenPHP](https://frankenphp.dev/) - The modern PHP app server
- [Caddy](https://caddyserver.com/) - The web server powering FrankenPHP
- [Laravel](https://laravel.com/) - The PHP framework for web artisans

## Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Check existing issues and pull requests
- Review the documentation and examples

## Acknowledgments

Built with:
- FrankenPHP by Kévin Dunglas
- Caddy web server
- PHP community extensions
- Open-source tooling ecosystem
