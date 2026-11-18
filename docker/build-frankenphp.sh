#!/usr/bin/env bash
set -euo pipefail
set -x

if [[ ! "$FRANKENPHP_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ||
      ! "$FRANKENPHP_REVISION" =~ ^[a-f0-9]{40}$ ]]; then
    echo "Set FRANKENPHP_VERSION and FRANKENPHP_REVISION to a stable tag and its commit. Run the source resolver first." >&2
    exit 1
fi

fetch() {
    local url="$1" ref="$2" destination="$3"
    git init -q "$destination"
    git -C "$destination" fetch -q --depth 1 "$url" "$ref"
    git -C "$destination" checkout -q FETCH_HEAD
}

fetch https://github.com/php/frankenphp.git "$FRANKENPHP_REVISION" /usr/src/frankenphp
cd /usr/src/frankenphp
[[ "$(git rev-parse HEAD)" == "$FRANKENPHP_REVISION" ]]

# Use the same watcher C source as the Go module pinned by FrankenPHP, rather
# than resolving a mutable "latest" asset during compilation.
watcher_dir="$(go mod download -json github.com/e-dant/watcher | jq -er '.Dir')"
cmake -S "$watcher_dir" -B /tmp/watcher-build \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-error=use-after-free" \
    -DCMAKE_INSTALL_LIBDIR=lib
cmake --build /tmp/watcher-build --parallel "$(nproc)"
cmake --install /tmp/watcher-build

# Bookworm's packaged Brotli is too old for cbrotli. Use the same pinned
# release and checksum as upstream FrankenPHP for that suite.
output=/out/frankenphp
if ! pkg-config --atleast-version=1.1 libbrotlienc; then
    mkdir -p /tmp/brotli "$output/etc/ld.so.conf.d"
    curl --retry 3 -fsSL -o /tmp/brotli.tar.gz https://github.com/google/brotli/archive/refs/tags/v1.2.1.tar.gz
    echo "98d35d11a78dc453aebb7d10c3748f3f73ff78c8267c0dc697b8631f67bf7e8f  /tmp/brotli.tar.gz" | sha256sum --check --strict
    tar -xzf /tmp/brotli.tar.gz -C /tmp/brotli --strip-components=1
    cmake -S /tmp/brotli -B /tmp/brotli/build -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build /tmp/brotli/build --parallel "$(nproc)"
    cmake --install /tmp/brotli/build
    install -D -m 0644 /tmp/brotli/LICENSE "$output/usr/local/share/licenses/brotli/LICENSE"
    # Prefer these shared libs over the suite's multiarch library directory.
    echo /usr/local/lib > /etc/ld.so.conf.d/000-frankenphp-brotli.conf
    cp /etc/ld.so.conf.d/000-frankenphp-brotli.conf "$output/etc/ld.so.conf.d/"
    mkdir -p "$output/usr/local/lib"
    cp -a /usr/local/lib/libbrotli*.so* "$output/usr/local/lib/"
fi
ldconfig

# Use the released server entry point and its go.sum instead of rebuilding
# via xcaddy with potentially different default Caddy modules or dependencies.
export CGO_ENABLED=1
export CGO_CFLAGS="-DFRANKENPHP_VERSION=${FRANKENPHP_VERSION} ${PHP_CFLAGS}"
export CGO_CPPFLAGS="$PHP_CPPFLAGS"
export CGO_LDFLAGS="-L/usr/local/lib -lssl -lcrypto -lreadline -largon2 -lcurl -lonig -lz ${PHP_LDFLAGS}"

mkdir -p "$output"/{usr/local/bin,usr/local/lib,etc/caddy,etc/frankenphp,app/public}
(
    cd caddy/frankenphp
    ../../go.sh build \
        -ldflags "-w -s -X 'github.com/caddyserver/caddy/v2.CustomVersion=FrankenPHP ${FRANKENPHP_VERSION} PHP ${PHP_VERSION} Caddy' -X 'github.com/caddyserver/caddy/v2.CustomBinaryName=frankenphp' -X 'github.com/caddyserver/caddy/v2/modules/caddyhttp.ServerHeader=FrankenPHP Caddy'" \
        -buildvcs=true -o "$output/usr/local/bin/frankenphp" .
)
cp -a /usr/local/lib/libwatcher*.so* "$output/usr/local/lib/"
install -m 0644 caddy/frankenphp/Caddyfile "$output/etc/caddy/Caddyfile"
install -D -m 0644 LICENSE "$output/usr/local/share/licenses/frankenphp/LICENSE"
install -D -m 0644 "$watcher_dir/license" "$output/usr/local/share/licenses/watcher/LICENSE"
ln "$output/etc/caddy/Caddyfile" "$output/etc/frankenphp/Caddyfile"
install -m 0644 package/content/index.php "$output/app/public/index.php"
"$output/usr/local/bin/frankenphp" version
