variable "IMAGE_NAME" {
    default = "ghcr.io/prvious/frankenphp"
}

variable "PHP_VERSION" {
    description = "Comma-separated list of PHP minor versions to build, e.g. '8.4,8.5'."
    default = "8.4,8.5"
}

variable "SHA" {
    description = "Git commit SHA for OCI revision labels; defaults to 'local' for local builds."
    default = "local"
}

variable "LATEST" {
    description = "The PHP minor version to publish under the latest aliases."
    default = "8.5"
}

variable "REFRESH" {
    description = "Optional cache-busting value for floating upstream dependencies."
    default = ""
}

function "tag" {
    params = [name, os, variant]
    result = "${IMAGE_NAME}:${name}${os == "trixie" ? "" : "-${os}"}${variant == "dev" ? "-dev" : ""}"
}

target "default" {
    name = "runner-php-${replace(php_version, ".", "-")}-${os}-${variant}"
    matrix = {
        php_version = split(",", replace(PHP_VERSION, " ", ""))
        os = ["bookworm", "trixie"]
        variant = ["prod", "dev"]
    }
    dockerfile = "Dockerfile"
    context = "./"
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]

    target = variant
    pull = true

    tags = distinct(concat(
        [tag("php${php_version}", os, variant)],
        php_version == LATEST ? [
            tag("php${split(".", php_version)[0]}", os, variant),
            tag("latest", os, variant),
        ] : [],
    ))

    args = {
        VERSION = "${php_version}-${os}"
        REFRESH = REFRESH
    }

    labels = {
        "org.opencontainers.image.description" = variant == "dev" ? "FrankenPHP Docker images (${os}) with supervisor, Node.js 26, pnpm, sqlsrv, Xdebug, and development tools." : "FrankenPHP Docker images (${os}) with supervisor, Node.js 26, pnpm, sqlsrv, and image tools."
        "org.opencontainers.image.created" = "${timestamp()}"
        "org.opencontainers.image.version" = variant == "dev" ? "${php_version}-${os}-dev" : "${php_version}-${os}"
        "org.opencontainers.image.revision" = SHA
    }
}
