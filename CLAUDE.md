# Agent Guidelines for FrankenPHP Docker Images

## Build Commands

-   **Build all variants**: `docker buildx bake`
-   **Build specific variant**: `docker buildx bake runner-php-8-4-bookworm`
-   **Build with push**: `docker buildx bake --push`
-   **Print build matrix**: `docker buildx bake --print`

## Test Commands

-   **Test image**: `docker run --rm -it <image> php -v`
-   **Test container**: `docker run --rm -p 80:80 <image>`
-   **Run with shell**: `docker run --rm -it <image> bash`

## Available Aliases (from env.sh)

-   `pint` - Laravel Pint formatter: `./vendor/bin/pint`
-   `pa` - PHP Artisan: `php artisan`
-   `stan`/`phpstan` - PHPStan: `./vendor/bin/phpstan`
-   `pest` - Pest testing: `./vendor/bin/pest`
-   `amf` - Migrate fresh: `php artisan migrate:fresh`
-   `amfs` - Migrate fresh with seed: `php artisan migrate:fresh --seed`

## Code Style Guidelines

-   **HCL**: 4-space indentation, descriptive variables (e.g., `IMAGE_NAME`, `PHP_VERSION`)
-   **Shell**: Use `set -exo pipefail`, proper quoting, environment variable prefixes
-   **Docker**: Multi-platform builds (`linux/amd64`, `linux/arm64`), proper labels
-   **Tags**: Use semantic versioning, clean tag function for sanitization
-   **Functions**: HCL functions for reusable logic (tag generation, version parsing)
-   **Matrix builds**: Support multiple PHP versions and OS variants
-   **Labels**: Include OpenContainers standard labels with metadata
