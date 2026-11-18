#!/usr/bin/env bash
# Offline regression checks for source resolution and scheduled rebuilds.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" GH_TOKEN=fixture-token
export FIXTURE_PHP_RELEASES='{"8.4":"8.4.27","8.5":"8.5.12","8.6":"8.6.1"}'
export FIXTURE_OLD_PHP_VERSION=8.4.26
export FIXTURE_PHP_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export FIXTURE_FRANKENPHP_VERSION=v1.13.5
export FIXTURE_FRANKENPHP_REVISION=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
mkdir "$tmp/bin"

jq -n '
    (env.FIXTURE_PHP_RELEASES | fromjson) as $releases
    | {target: (reduce ("8.4", "8.5") as $minor ({};
        reduce ("prod", "dev") as $variant (.;
            .["runner-php-\($minor | sub("\\."; "-"))-trixie-\($variant)"] = {
                target: $variant,
                args: {
                    PHP_MINOR: $minor, DEBIAN_SUITE: "trixie", PHP_VERSION: $releases[$minor],
                    FRANKENPHP_VERSION: env.FIXTURE_FRANKENPHP_VERSION,
                    FRANKENPHP_REVISION: env.FIXTURE_FRANKENPHP_REVISION
                },
                tags: ["example:test"], platforms: ["linux/amd64", "linux/arm64"]
            }
        )
    ))}' > "$tmp/metadata.json"

cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
url="${@: -1}"
printf '%s\n' "$url" >> "$CALLS"
auth=false
for arg; do [[ "$arg" != "Authorization: Bearer fixture-token" ]] || auth=true; done
case "$url" in
    https://www.php.net/releases/*)
        [[ "$auth" == false ]]
        version="$(jq -er --arg minor "${url##*=}" '.[$minor]' <<< "$FIXTURE_PHP_RELEASES")"
        [[ "$CASE" != wrong-minor ]] || version=8.3.42
        checksum="$FIXTURE_PHP_SHA256"
        [[ "$CASE" != bad-checksum ]] || checksum=invalid
        jq -n --arg version "$version" --arg sha "$checksum" \
            '{version: $version, source: [{filename: "php-\($version).tar.xz", sha256: $sha}]}'
        ;;
    https://api.github.com/repos/php/frankenphp/releases/latest)
        [[ "$auth" == true ]]
        prerelease=false
        [[ "$CASE" != prerelease ]] || prerelease=true
        jq -n --argjson prerelease "$prerelease" \
            '{tag_name: env.FIXTURE_FRANKENPHP_VERSION, draft: false, prerelease: $prerelease}'
        ;;
    "https://api.github.com/repos/php/frankenphp/commits/$FIXTURE_FRANKENPHP_VERSION")
        [[ "$auth" == true ]]
        sha="$FIXTURE_FRANKENPHP_REVISION"
        [[ "$CASE" != bad-revision ]] || sha=invalid
        jq -n --arg sha "$sha" '{sha: $sha}'
        ;;
    *) exit 1 ;;
esac
MOCK

cat > "$tmp/bin/date" <<'MOCK'
#!/bin/sh
echo 2
MOCK

cat > "$tmp/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    *" --raw "*)
        jq -n '{manifests: [("amd64", "arm64") |
            {platform: {os: "linux", architecture: .}, digest: "sha256:\(.)"}]}'
        ;;
    *" --format "*)
        ref="${@: -1}"
        if [[ "$CASE" == missing ]]; then
            echo '{"config":{"Labels":{}}}'
            exit 0
        fi
        version="$(jq -er '.["8.4"]' <<< "$FIXTURE_PHP_RELEASES")"
        [[ "$CASE" != old-arm || "$ref" != *arm64 ]] || version="$FIXTURE_OLD_PHP_VERSION"
        jq -n --arg version "$version" '{config: {Labels: {
            "org.opencontainers.image.php.version": $version,
            "org.opencontainers.image.frankenphp.version": env.FIXTURE_FRANKENPHP_VERSION,
            "org.opencontainers.image.frankenphp.revision": env.FIXTURE_FRANKENPHP_REVISION
        }}}'
        ;;
    *"apt-get update"*)
        [[ "$CASE" != apt-error ]] || exit 1
        if [[ "$CASE" == apt-update ]]; then echo 1; else echo 0; fi
        ;;
    *) printf 'v26.0.0\n11.0.0\n4.0.0\n' ;;
esac
MOCK

chmod +x "$tmp/bin/"*
# The planner fixture isolates one PHP minor and exercises both platforms.
jq '.target |= with_entries(select(.value.args.PHP_MINOR == "8.4"))' \
    "$tmp/metadata.json" > "$tmp/planner.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
resolve() { CASE="$1" bash "$repo/docker/resolve-sources.sh" < "$tmp/metadata.json"; }
plan() { CASE="$1" bash "$repo/.github/scripts/plan-scheduled-build.sh" "$tmp/planner.json"; }

resolve same > "$tmp/resolved.json"
jq -e --slurpfile metadata "$tmp/metadata.json" '
    (.target | length) == 4 and all(.target | to_entries[];
        .value.args.PHP_VERSION == $metadata[0].target[.key].args.PHP_VERSION
        and .value.args.PHP_SHA256 == env.FIXTURE_PHP_SHA256
        and .value.args.FRANKENPHP_VERSION == env.FIXTURE_FRANKENPHP_VERSION
        and .value.args.FRANKENPHP_REVISION == env.FIXTURE_FRANKENPHP_REVISION)' "$tmp/resolved.json" > /dev/null
[[ "$(wc -l < "$CALLS")" -eq 4 ]] || fail "expected one lookup per PHP minor, one FrankenPHP release and one commit"

# A new minor or suite in Bake needs no resolver changes. The compiler owns the signing keys.
printf '%s\n' '{"target":{"local-dev":{"args":{"PHP_MINOR":"8.6","DEBIAN_SUITE":"forky"}}}}' \
    | CASE=same bash "$repo/docker/resolve-sources.sh" \
    | jq -e '.target["local-dev"].args.PHP_VERSION == (env.FIXTURE_PHP_RELEASES | fromjson | .["8.6"])' > /dev/null

for scenario in wrong-minor bad-checksum prerelease bad-revision; do
    if resolve "$scenario" > "$tmp/output" 2> "$tmp/error"; then fail "resolver accepted $scenario"; fi
    [[ ! -s "$tmp/output" ]] || fail "resolver emitted partial output for $scenario"
done

[[ "$(plan same)" == '["php-8-4-trixie-dev"]' ]] || fail "unchanged sources should rebuild only dev"
for scenario in old-arm missing apt-update; do
    [[ "$(plan "$scenario")" == '["php-8-4-trixie-dev","php-8-4-trixie-prod"]' ]] || fail "$scenario should rebuild dev and prod"
done
if plan apt-error > "$tmp/output" 2> "$tmp/error"; then fail "planner ignored apt error"; fi

echo "Source resolver and scheduled build planner checks passed."
