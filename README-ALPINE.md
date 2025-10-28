# Alpine Docker Images for FrankenPHP

This repository now supports both **Bookworm** (Debian) and **Alpine** Linux based Docker images for FrankenPHP.

## Available Image Variants

### Bookworm (Debian-based)
- **Production**: `ghcr.io/prvious/frankenphp:php8.x-bookworm`
- **Development**: `ghcr.io/prvious/frankenphp:php8.x-bookworm-dev`

### Alpine (Alpine Linux-based)
- **Production**: `ghcr.io/prvious/frankenphp:php8.x-alpine`
- **Development**: `ghcr.io/prvious/frankenphp:php8.x-alpine-dev`

## Build Commands

### Build All Variants
```bash
docker buildx bake
```

### Build Specific OS Variants
```bash
# All Bookworm variants
docker buildx bake --set="*.name=*bookworm*"

# All Alpine variants  
docker buildx bake --set="*.name=*alpine*"
```

### Build Development Images Only
```bash
docker buildx bake dev
```

### Build Production Images Only
```bash
docker buildx bake prod
```

### Build Specific Image
```bash
# Alpine PHP 8.4 Development
docker buildx bake runner-php-8-4-alpine-dev

# Bookworm PHP 8.3 Production
docker buildx bake runner-php-8-3-bookworm-production
```

## Functionality Comparison

Both Alpine and Bookworm variants provide the same functionality:

### Base Features
- ✅ FrankenPHP server
- ✅ PHP with all extensions (mysqli, pdo_mysql, pgsql, bcmath, gd, imagick, etc.)
- ✅ Node.js via FNM (Fast Node Manager)
- ✅ Supervisor process manager
- ✅ PostgreSQL and MySQL clients

### Development Features (in -dev variants)
- ✅ Xdebug PHP extension
- ✅ Playwright for browser automation and testing
- ✅ GitHub CLI (`gh`)
- ✅ Developer tools (htop, nano, starship prompt)
- ✅ Zsh with Oh My Zsh and plugins
- ✅ Custom aliases and environment

### Image Optimization Tools
- ✅ jpegoptim, optipng, pngquant, gifsicle
- ✅ libavif (AVIF image support)
- ✅ FFmpeg for media processing

## Key Differences

| Feature | Bookworm | Alpine |
|---------|----------|--------|
| Base OS | Debian 12 (Bookworm) | Alpine Linux 3.22 |
| Package Manager | `apt` | `apk` |
| Image Size | Larger (~500MB+) | Smaller (~200MB+) |
| Compatibility | Broader compatibility | Musl libc (some limitations) |
| Security Updates | Regular Debian security updates | Alpine security updates |

## Usage Examples

### Run Alpine Production Container
```bash
docker run --rm -p 80:80 ghcr.io/prvious/frankenphp:php8.4-alpine
```

### Run Bookworm Development Container
```bash
docker run --rm -it ghcr.io/prvious/frankenphp:php8.3-bookworm-dev bash
```

### Test Container Functionality
```bash
docker run --rm -v "$PWD/test.php:/test.php:ro" ghcr.io/prvious/frankenphp:php8.4-alpine php /test.php production
```

## Environment Variables and Configuration

Both variants support the same environment variables and configuration options as defined in `env.sh`:

```bash
# Available aliases in both variants
pint      # Laravel Pint formatter
pa        # PHP Artisan
stan      # PHPStan
pest      # Pest testing
amf       # Artisan migrate:fresh
amfs      # Artisan migrate:fresh --seed
```

## Build Matrix

The build system automatically creates the following matrix:

```
PHP Versions: 8.3, 8.4
OS Variants: bookworm, alpine  
Build Types: dev, prod
Platforms: linux/amd64, linux/arm64
```

This generates 16 total image variants (2 PHP × 2 OS × 2 types × 2 platforms).

## Development

### File Structure
- `Dockerfile` - Bookworm variant
- `alpine.Dockerfile` - Alpine variant  
- `docker-bake.hcl` - Build configuration
- `env.sh` - Shared environment setup
- `test.php` - Functionality testing script

### Adding New Features
When adding new functionality, ensure both `Dockerfile` and `alpine.Dockerfile` are updated to maintain parity between variants.