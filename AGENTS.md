# Repository Guidelines

## Project Structure & Module Organization

This repository builds the `ghcr.io/prvious/frankenphp` development and production images. `Dockerfile` defines the PHP and FrankenPHP source builds, binary/tool builders, and the shared `base`, `dev`, and `prod` stages. Source build scripts and release resolution live under `docker/`. `docker-bake.hcl` expands PHP versions and targets across `linux/amd64` and `linux/arm64`. Container behavior is configured by `.env`, `.zshrc`, and `.zshrc.prod`. Executable Laravel health checks live under `usr/local/bin/`. Image validation is centralized in `test.php`, while `.github/workflows/pipeline.yml` builds, tests, and publishes the matrix.

## Build, Test, and Development Commands

- `docker buildx bake --print` inspects the default PHP 8.4/8.5/8.6 minor-version matrix. Override `PHP_VERSION`, `LATEST`, `SHA`, and `REFRESH` when testing matrix or dependency-refresh changes.
- `docker buildx bake --print | bash docker/resolve-sources.sh > /tmp/frankenphp-sources.json` resolves the stable source versions for the matrix.
- `docker buildx bake -f docker-bake.hcl -f /tmp/frankenphp-sources.json` builds all configured variants and architectures. See README for loading one target locally.
- `bash .github/scripts/test-source-build.sh` tests source resolution and scheduled rebuild planning without a Docker daemon.
- `docker run --rm -v "$PWD/test.php:/app/test.php" frankenphp:dev php /app/test.php dev` validates extensions, binaries, and pnpm configuration. Substitute the production image and `production` for that target.

## Coding Style & Naming Conventions

Use four-space indentation in PHP, HCL, and workflow YAML. Keep PHP strictly typed and follow the existing PSR-12-style class and method layout; use `camelCase` methods and `UPPER_SNAKE_CASE` constants. In Dockerfile steps, group related packages, use uppercase build arguments, quote shell variables, and clean package caches in the same layer. Health-check filenames use the `healthcheck-<service>` pattern; the Dockerfile copies them into the image as executable POSIX shell scripts.

## Testing Guidelines

There is no external test framework or coverage threshold. `test.php` is the acceptance suite. Update its expected extension and binary arrays whenever image contents change, then test both `dev` and `production`. For architecture-sensitive changes, run the Buildx matrix or rely on the PR workflow for both supported platforms.

## Commit & Pull Request Guidelines

Prefer short, imperative Conventional Commit subjects such as `feat: add healthcheck script`, `fix: correct pnpm path`, or `chore: remove package`; avoid `wip` commits in review-ready branches. Pull requests should explain the affected stage or variant, note tag/platform impact, link relevant issues, and list exact build and test commands with results. Screenshots are only useful for user-visible shell behavior.

## Security & Configuration

`.env` is copied into `/etc/profile.d/.env`; keep it limited to non-secret container defaults and aliases. Never commit registry tokens, credentials, or application secrets.
