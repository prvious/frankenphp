#!/usr/bin/env bash
# Read Docker Bake --print JSON from stdin and write a Bake override to stdout.
set -euo pipefail

fetch() {
    local url="$1"
    local options=(--fail --silent --show-error --location --retry 3 --retry-max-time 90
        --max-time 45 --proto '=https' --user-agent prvious-frankenphp-source-builder)
    if [[ "$url" == https://api.github.com/* && -n "${GH_TOKEN:-}" ]]; then
        options+=(--header "Authorization: Bearer ${GH_TOKEN}")
    fi
    curl "${options[@]}" "$url"
}

targets="$(jq -ce '.target | with_entries(select(.key | startswith("runner-")))
    | if length > 0 then . else error("No runner targets in Bake metadata") end')"
minors="$(jq -er '
    [.[].args.VERSION
        | if type == "string" and test("^8\\.[45]-(bookworm|trixie)$")
          then split("-")[0] else error("Unsupported PHP target: \(.)") end]
    | unique[]' <<< "$targets")"
releases='{}'

while IFS= read -r minor; do
    php="$(fetch "https://www.php.net/releases/?json&version=${minor}" | jq -ce --arg minor "$minor" '
        .version as $version
        | if ($version | test("^8\\.[45]\\.[0-9]+$") and startswith($minor + "."))
          then . else error("Unexpected PHP release: \($version)") end
        | [.source[] | select(.filename == "php-\($version).tar.xz") | .sha256] as $checksums
        | if ($checksums | length) == 1 and ($checksums[0] | test("^[a-f0-9]{64}$"))
          then {PHP_VERSION: $version, PHP_SHA256: $checksums[0]}
          else error("Missing or invalid PHP archive checksum") end')"
    releases="$(jq -c --arg minor "$minor" --argjson php "$php" '.[$minor] = $php' <<< "$releases")"
done <<< "$minors"

frankenphp="$(fetch https://api.github.com/repos/php/frankenphp/releases/latest | jq -er '
    if .draft == false and .prerelease == false and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
    then .tag_name else error("Expected a stable FrankenPHP release tag") end')"
revision="$(fetch "https://api.github.com/repos/php/frankenphp/commits/${frankenphp}" | jq -er '
    .sha | if test("^[a-f0-9]{40}$") then . else error("Invalid FrankenPHP commit") end')"

jq --argjson releases "$releases" --arg frankenphp "$frankenphp" --arg revision "$revision" '
    {target: with_entries(.value = {
        args: ($releases[.value.args.VERSION | split("-")[0]] + {
            FRANKENPHP_VERSION: $frankenphp,
            FRANKENPHP_REVISION: $revision
        })
    })}' <<< "$targets"
