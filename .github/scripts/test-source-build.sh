#!/usr/bin/env bash
# Offline regression checks for source resolution and scheduled rebuilds.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export PATH="$tmp/bin:$PATH" CALLS="$tmp/calls" GH_TOKEN=fixture-token
export SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export CHECKSUM=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
mkdir "$tmp/bin"

jq -n --arg sha "$SHA" '
    {target: (reduce ("8.4", "8.5") as $minor ({};
        reduce ("prod", "dev") as $variant (.;
            .["runner-php-\($minor | sub("\\."; "-"))-trixie-\($variant)"] = {
                target: $variant,
                args: {
                    VERSION: "\($minor)-trixie", PHP_VERSION: "\($minor).27",
                    FRANKENPHP_VERSION: "v1.13.5", FRANKENPHP_REVISION: $sha
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
        version="${url##*=}.27"
        [[ "$CASE" != wrong-minor ]] || version=8.3.42
        checksum="$CHECKSUM"
        [[ "$CASE" != bad-checksum ]] || checksum=invalid
        jq -n --arg version "$version" --arg sha "$checksum"             '{version: $version, source: [{filename: "php-\($version).tar.xz", sha256: $sha}]}'
        ;;
    https://api.github.com/repos/php/frankenphp/releases/latest)
        [[ "$auth" == true ]]
        prerelease=false
        [[ "$CASE" != prerelease ]] || prerelease=true
        jq -n --argjson prerelease "$prerelease"             '{tag_name: "v1.13.5", draft: false, prerelease: $prerelease}'
        ;;
    https://api.github.com/repos/php/frankenphp/commits/v1.13.5)
        [[ "$auth" == true ]]
        sha="$SHA"
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
        version=8.4.27
        [[ "$CASE" != old-arm || "$ref" != *arm64 ]] || version=8.4.26
        jq -n --arg version "$version" --arg sha "$SHA" '{config: {Labels: {
            "org.opencontainers.image.php.version": $version,
            "org.opencontainers.image.frankenphp.version": "v1.13.5",
            "org.opencontainers.image.frankenphp.revision": $sha
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
jq '.target |= with_entries(select(.key | startswith("runner-php-8-4-")))'     "$tmp/metadata.json" > "$tmp/planner.json"

fail() { echo "FAIL: $*" >&2; exit 1; }
resolve() { CASE="$1" bash "$repo/docker/resolve-sources.sh" < "$tmp/metadata.json"; }
plan() { CASE="$1" bash "$repo/.github/scripts/plan-scheduled-build.sh" "$tmp/planner.json"; }

resolve same > "$tmp/resolved.json"
jq -e --arg sha "$SHA" --arg checksum "$CHECKSUM" '
    (.target | length) == 4 and all(.target | to_entries[];
        .value.args.PHP_VERSION == (if .key | startswith("runner-php-8-4-") then "8.4.27" else "8.5.27" end)
        and .value.args.PHP_SHA256 == $checksum
        and .value.args.FRANKENPHP_VERSION == "v1.13.5"
        and .value.args.FRANKENPHP_REVISION == $sha)' "$tmp/resolved.json" > /dev/null
[[ "$(wc -l < "$CALLS")" -eq 4 ]] || fail "expected one lookup per PHP minor, one FrankenPHP release and one commit"

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
