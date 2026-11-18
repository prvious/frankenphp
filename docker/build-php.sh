#!/usr/bin/env bash
# Build the CLI and shared, thread-safe libphp from the same php.net release.
set -euo pipefail
set -x

minor="${PHP_VERSION%.*}"
case "$minor" in
    8.4)
        keys=(AFD8691FDAEDF03BDF6E460563F15A9B715376CA 9D7F99A0CB8F05C8A6958D6256A97AF7600A39A6 0616E93D95AF471243E26761770426E17EBBB3DD)
        ;;
    8.5)
        keys=(1198C0117593497A5EC5C199286AF1F9897469DC 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4 D95C03BC702BE9515344AE3374E44BC9067701A5)
        ;;
    *)
        echo "Unsupported or missing PHP_VERSION: ${PHP_VERSION}" >&2
        exit 1
        ;;
esac

if [[ ! "$PHP_VERSION" =~ ^8\.[45]\.[0-9]+$ ||
      ! "$PHP_SHA256" =~ ^[a-f0-9]{64}$ ||
      "$VERSION" != "${minor}-${DEBIAN_SUITE}" ]]; then
    echo "PHP_VERSION and PHP_SHA256 must describe a stable release for VERSION=${VERSION} on ${DEBIAN_SUITE}. Run the source resolver first." >&2
    exit 1
fi

mkdir -p /usr/src
url="https://www.php.net/distributions/php-${PHP_VERSION}.tar.xz"
curl --retry 3 -fsSL -o /usr/src/php.tar.xz "$url"
echo "${PHP_SHA256}  /usr/src/php.tar.xz" | sha256sum --check --strict

# Official PHP release signing fingerprints: https://www.php.net/gpg-keys.php
# The temporary verification keyring contains only the pinned fingerprints.
export GNUPGHOME="$(mktemp -d)"
trap 'rm -rf "$GNUPGHOME"' EXIT
curl --retry 3 -fsSL -o "$GNUPGHOME/php.asc" "${url}.asc"
for key in "${keys[@]}"; do
    curl --retry 3 -fsSL -o "$GNUPGHOME/key.asc" \
        "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x${key}"
    fingerprint="$(gpg --batch --with-colons --show-keys "$GNUPGHOME/key.asc" | awk -F: '
        $1 == "pub" { primary = 1; next }
        $1 == "fpr" && primary { print $10; primary = 0 }
    ')"
    [[ "$fingerprint" == "$key" ]]
    gpg --batch --dearmor < "$GNUPGHOME/key.asc" >> "$GNUPGHOME/release-keys.gpg"
done
gpgv --keyring "$GNUPGHOME/release-keys.gpg" "$GNUPGHOME/php.asc" /usr/src/php.tar.xz

docker-php-source extract
cd /usr/src/php

export CFLAGS="$PHP_CFLAGS" CPPFLAGS="$PHP_CPPFLAGS" LDFLAGS="$PHP_LDFLAGS"
export PHP_BUILD_PROVIDER='https://github.com/prvious/frankenphp' PHP_UNAME='Linux - Docker'
arch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"
multiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"

# Match the PHP ZTS image's core extension set, ini locations and toolchain
# interface so existing PHP configuration and downstream extension builds work.
# OPcache is shared in PHP 8.4 and built in from PHP 8.5.
opcache=()
if [[ "$minor" == 8.4 ]]; then
    opcache=(--enable-opcache=shared)
fi

./configure \
    --build="$arch" \
    --sysconfdir="${PHP_INI_DIR%/php}" \
    --with-config-file-path="$PHP_INI_DIR" \
    --with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
    --enable-option-checking=fatal \
    --enable-zts \
    --enable-embed=shared \
    --disable-zend-signals \
    --with-pic \
    --with-mhash \
    --enable-mbstring \
    --enable-mysqlnd \
    --with-password-argon2 \
    --with-sodium=shared \
    --with-pdo-sqlite=/usr \
    --with-sqlite3=/usr \
    --with-curl \
    --with-iconv \
    --with-openssl \
    --with-readline \
    --with-zlib \
    --enable-phpdbg \
    --enable-phpdbg-readline \
    --with-pear \
    --with-libdir="lib/${multiarch}" \
    "${opcache[@]}"

make -j "$(nproc)"
make install
find /usr/local/bin /usr/local/lib -type f \( -perm /0111 -o -name '*.so*' \) \
    -exec sh -c 'for f do if file -b "$f" | grep -q "^ELF"; then strip --strip-unneeded "$f"; fi; done' sh {} +
mkdir -p "$PHP_INI_DIR/conf.d"
cp php.ini-development php.ini-production "$PHP_INI_DIR/"
install -D -m 0644 LICENSE /usr/local/share/licenses/php/LICENSE
ldconfig
docker-php-ext-enable sodium
if [[ "$minor" == 8.4 ]]; then
    docker-php-ext-enable opcache
fi
php -r 'exit(PHP_ZTS && PHP_VERSION === getenv("PHP_VERSION") && extension_loaded("Zend OPcache") ? 0 : 1);'
pecl update-channels
rm -rf /tmp/pear /root/.pearrc
cd /
docker-php-source delete

# Compute the runtime package set on this Debian suite/architecture, rather than
# copying system libraries or hardcoding names that change with Debian's t64 ABI.
# Detect any missing libraries here instead of producing an unusable image.
mkdir -p /out
{
    ldd /usr/local/bin/php /usr/local/bin/phpdbg /usr/local/lib/libphp.so
    find /usr/local/lib/php/extensions -type f -name '*.so' -exec ldd {} +
} > /tmp/php-ldd
if grep -q 'not found' /tmp/php-ldd; then
    cat /tmp/php-ldd >&2
    exit 1
fi
# Package-owner records begin with a package token ending in a colon;
# Trixie usrmerge also emits human-readable diversion records that do not.
awk '/=>/ && $3 ~ /^\// && $3 !~ /^\/usr\/local\// {
    sub(/^\/(usr\/)?/, "", $3); print "*" $3
}' /tmp/php-ldd \
    | sort -u \
    | xargs -r dpkg-query --search \
    | awk 'sub(/:$/, "", $1) { print $1 }' \
    | sort -u > /out/php-runtime-packages
test -s /out/php-runtime-packages
rm /tmp/php-ldd
