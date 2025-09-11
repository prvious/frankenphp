variable "IMAGE_NAME" {
    default = "ghcr.io/prvious/frankenphp"
}

variable "PHP_VERSION" {}

variable "SHA" {}

variable "VERSION" {}

variable "LATEST" {}

function "clean_tag" {
    params = [tag]
    result = substr(regex_replace(regex_replace(tag, "[^\\w.-]", "-"), "^([^\\w])", "r$0"), 0, 127)
}

function "tag" {
    params = [php_version]
    result = [
       "${IMAGE_NAME}:php${php_version}",
        php_version == LATEST ? "${IMAGE_NAME}:latest" : ""
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

group "dev" {
    targets = flatten([
        for pv in split(",", replace(PHP_VERSION, " ", "")) : [
            "runner-php-${replace(pv, ".", "-")}-bookworm-dev",
            "runner-php-${replace(pv, ".", "-")}-alpine-dev"
        ]
    ])
}

group "prod" {
    targets = flatten([
        for pv in split(",", replace(PHP_VERSION, " ", "")) : [
            "runner-php-${replace(pv, ".", "-")}-bookworm-production",
            "runner-php-${replace(pv, ".", "-")}-alpine-production"
        ]
    ])
}

target "default" {
    name = "${tgt}-php-${replace(php_version, ".", "-")}-${os}${variant == "dev" ? "-dev" : "-production"}"
    matrix = {
        php_version = split(",", replace(PHP_VERSION, " ", ""))
        os = ["bookworm", "alpine"]
        tgt = ["runner"]
        variant = ["prod", "dev"]
    }
    dockerfile = os == "alpine" ? "alpine.Dockerfile" : "Dockerfile"
    context = "./"
    contexts = {
        php-base = "docker-image://php:${php_version}-zts-${os}"
    }
    platforms = [
        "linux/amd64",
        "linux/arm64"
    ]
    
    target = variant
    
    tags = distinct(flatten(
        variant == "dev" ? 
        # Dev variant: add -dev suffix to all tags
        [for pv in php_version(php_version) : flatten([
            [for tag_val in tag(pv) : tag_val == "" ? "" : "${tag_val}-${os}-dev"],
            [for v in semver(VERSION) : [for tag_val in tag(pv) : tag_val == "" ? "" : "${tag_val}-${os}-dev"]]
        ])] :
        [for pv in php_version(php_version) : flatten([
            [for tag_val in tag(pv) : tag_val == "" ? "" : "${tag_val}-${os}"],
            [for v in semver(VERSION) : [for tag_val in tag(pv) : tag_val == "" ? "" : "${tag_val}-${os}"]]
        ])]
    ))
    
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
