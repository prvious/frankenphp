variable "IMAGE_NAME" {
    default = "ghcr.io/prvious/frankenphp"
}

variable "PHP_VERSION" {
    description = "Comma-separated list of PHP versions to build, e.g. '8.1.0,8.2.0,8.3.0'."
}

variable "SHA" {
    description = "The git commit SHA to use for the build."
}

variable "LATEST" {
    description = "The latest PHP version to use for tagging the 'latest' tag."
}

function "clean_tag" {
    params = [tag]
    result = substr(regex_replace(regex_replace(tag, "[^\\w.-]", "-"), "^([^\\w])", "r$0"), 0, 127)
}

function "stripOS" {
    params = [tag]
    result = replace(tag, "-bookworm", "")
}

function "tag" {
    params = [php_version, os, variant, version]
    result = distinct(flatten([
        for pv in php_version(php_version) : flatten([
            // Base tags with OS and variant
            ["${IMAGE_NAME}:php${pv}-${os}${variant == "dev" ? "-dev" : ""}"],
            // Latest tags for the LATEST PHP version
            pv == LATEST ? ["${IMAGE_NAME}:latest-${os}${variant == "dev" ? "-dev" : ""}"] : [],
            // Semver tags with OS and variant (only if version is not empty and semver returns results)
            [for v in (semver(version)) : "${IMAGE_NAME}:php${v}-${os}${variant == "dev" ? "-dev" : ""}"],
        ])
    ]))
}

function "semver" {
  params = [rev]
  result = __semver(_semver(regexall("^v?(?P<major>0|[1-9]\\d*)\\.(?P<minor>0|[1-9]\\d*)\\.(?P<patch>0|[1-9]\\d*)(?:-(?P<prerelease>(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\\.(?:0|[1-9]\\d*|\\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\\.[0-9a-zA-Z-]+)*))?$", rev)))
}

function "_semver" {
    params = [matches]
    result = length(matches) == 0 ? {} : matches[0]
}

function "__semver" {
    params = [v]
    result = v.prerelease == null ? [v.major, "${v.major}.${v.minor}", "${v.major}.${v.minor}.${v.patch}"] : ["${v.major}.${v.minor}.${v.patch}-${v.prerelease}"]
}

function "php_version" {
    params = [v]
    result = _php_version(v, regexall("(?P<major>\\d+)\\.(?P<minor>\\d+)", v)[0])
}

function "_php_version" {
    params = [v, m]
    result = "${m.major}.${m.minor}" == "8.4" ? [v, "${m.major}.${m.minor}", "${m.major}"] : [v, "${m.major}.${m.minor}"]
}

target "default" {
    name = "${tgt}-php-${replace(php_version, ".", "-")}-${os}${variant == "dev" ? "-dev" : "-production"}"
    matrix = {
        php_version = split(",", replace(PHP_VERSION, " ", ""))
        os = ["bookworm"]
        tgt = ["runner"]
        variant = ["prod", "dev"]
    }
    dockerfile = "Dockerfile"
    context = "./"
    contexts = {
        php-base = "docker-image://php:${php_version}-zts-${os}"
    }
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]
    
    target = variant

    tags = [for t in tag(php_version, os, variant, clean_tag(php_version)) : stripOS(t)]
    
    args = {
        VERSION = "${clean_tag(php_version)}-${os}"
    }
    
    labels = {
        "org.opencontainers.image.description" = variant == "dev" ? "FrankenPHP Docker images (${os}) with supervisor, fnm(node version manager), pnpm, sqlsrv, Xdebug, and a few other goodies." : "FrankenPHP Docker images (${os}) with supervisor, fnm(node version manager), pnpm, sqlsrv, and a few other goodies."
        "org.opencontainers.image.created" = "${timestamp()}"
        "org.opencontainers.image.version" = variant == "dev" ? "${clean_tag(php_version)}-${os}-dev" : "${clean_tag(php_version)}-${os}"
        "org.opencontainers.image.revision" = SHA
    }
}
