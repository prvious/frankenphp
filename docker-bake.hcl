variable "IMAGE_NAME" {
    default = "ghcr.io/prvious/frankenphp"
}

variable "PHP_VERSION" {}

variable "VERSION" {}

variable "LATEST" {}

function "clean_tag" {
    params = [tag]
    result = substr(regex_replace(regex_replace(tag, "[^\\w.-]", "-"), "^([^\\w])", "r$0"), 0, 127)
}

function "tag" {
    params = [php-version]
    result = [
       "${IMAGE_NAME}:php${php-version}",
        php-version == LATEST ? "${IMAGE_NAME}:latest" : ""
    ]
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
    result = v == {} ? [clean_tag(VERSION)] : v.prerelease == null ? [v.major, "${v.major}.${v.minor}", "${v.major}.${v.minor}.${v.patch}"] : ["${v.major}.${v.minor}.${v.patch}-${v.prerelease}"]
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
    name = "${tgt}-php-${replace(php-version, ".", "-")}-${os}"
    matrix = {
        php-version = split(",", replace(PHP_VERSION, " ", ""))
        os = ["bookworm"]
        tgt = ["runner"]
    }
    dockerfile = "Dockerfile"
    context = "./"
    contexts = {
        php-base = "docker-image://php:${php-version}-zts-${os}"
    }
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]
    
    target = "runner"
    
    tags = distinct(flatten(
        [for pv in php_version(php-version) : flatten([
            tag(pv),
            [for v in semver(VERSION) : tag(pv)]
        ])
    ]))
    
    args = {
        VERSION = "${clean_tag(php-version)}"
    }
    labels = {
        "org.opencontainers.image.description" = "FrankenPHP Docker images with supervisor, fnm(node version manager), pnpm, sqlsrv, and a few other goodies."
        "org.opencontainers.image.created" = "${timestamp()}"
        "org.opencontainers.image.version" = "${clean_tag(php-version)}"
        "org.opencontainers.image.revision" = SHA
    }
}