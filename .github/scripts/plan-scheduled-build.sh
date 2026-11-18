#!/usr/bin/env bash
#
# Decides which variants a scheduled build publishes.
#
# Refreshing a production variant can give large package layers new digests,
# and every server running it then downloads them again. So the
# production variants are rebuilt only when something under them changed:
#
#   - the PHP or FrankenPHP source release used by a variant,
#   - a Debian or PostgreSQL package installed in a published image,
#   - Node (its major line), pnpm (its major line) or svgo,
#
# and on Mondays regardless, which picks up what these checks cannot see: new
# releases of the PHP extensions install-php-extensions builds, and Composer.
#
# Development variants are always rebuilt, to pick up the latest development
# tools. Prints the variants to build as a JSON array on stdout, and the reasons
# on stderr.
#
# Usage: plan-scheduled-build.sh <bake metadata JSON file>

set -euo pipefail

metadata="$1"
dockerfile="$(dirname "$0")/../../Dockerfile"
reasons=()

all_variants="$(jq -c '[.target | keys[] | select(startswith("runner-")) | sub("^runner-"; "")] | unique' "$metadata")"
dev_variants="$(jq -c 'map(select(endswith("-dev")))' <<< "${all_variants}")"

# Reject unresolved metadata rather than accidentally shifting empty TSV fields.
jq -e 'all(.target[] | select(.target == "prod");
    [.args.PHP_VERSION, .args.FRANKENPHP_VERSION, .args.FRANKENPHP_REVISION]
    | all(.[]; type == "string" and length > 0))' "$metadata" >/dev/null

if [[ "$(date -u +%u)" == 1 ]]; then
    reasons+=("weekly refresh (Monday)")
fi

# Read one platform's image configuration, without running foreign-architecture
# containers. Resolve the digest first so labels cannot come from another arch.
source_versions() {
    local ref="$1" platform="$2" index digest
    index="$(docker buildx imagetools inspect --raw "${ref}")" || return 1
    digest="$(jq -er --arg os "${platform%/*}" --arg arch "${platform#*/}" \
        'first(.manifests[] | select(.platform.os == $os and .platform.architecture == $arch) | .digest)' <<< "${index}")" || return 1
    docker buildx imagetools inspect --format '{{json .Image}}' "${ref%:*}@${digest}" \
        | jq -er '[.config.Labels["org.opencontainers.image.php.version"],
                    .config.Labels["org.opencontainers.image.frankenphp.version"],
                    .config.Labels["org.opencontainers.image.frankenphp.revision"]]
                   | if all(.[]; type == "string" and length > 0) then join(" ") else error("missing source labels") end'
}

# 1. Compare source versions resolved in prepare, not upstream image tags. A
# missing/unreadable label (including pre-migration images) triggers a rebuild.
while IFS=$'\t' read -r php frankenphp revision tag platforms; do
    [[ -n "${php}" && -n "${frankenphp}" && -n "${revision}" ]] || exit 1
    for platform in ${platforms//,/ }; do
        if ! ours="$(source_versions "${tag}" "${platform}" 2>/dev/null)"; then
            reasons+=("${tag} (${platform}) has no readable source versions")
        elif [[ "${ours}" != "${php} ${frankenphp} ${revision}" ]]; then
            reasons+=("${tag} (${platform}) needs PHP ${php}, FrankenPHP ${frankenphp} (${revision})")
        fi
    done
done < <(jq -r '.target[] | select(.target == "prod") | [.args.PHP_VERSION, .args.FRANKENPHP_VERSION, .args.FRANKENPHP_REVISION, .tags[0], (.platforms | join(","))] | @tsv' "$metadata")

# 2. Package updates, checked in one published production image per Debian
#    release: the package set is the same across PHP versions.
while IFS=$'\t' read -r os tag; do
    count="$(docker run --rm --quiet --pull always --user root --entrypoint bash "${tag}" -c \
        'set -eo pipefail; apt-get update -qq >/dev/null; apt list --upgradable 2>/dev/null | awk '\''/\[upgradable/ {count++} END {print count+0}'\''')"

    if [[ "${count}" -gt 0 ]]; then
        reasons+=("${count} package update(s) for ${os}")
    fi
done < <(jq -r '[.target[] | select(.target == "prod") | {os: (.args.VERSION | split("-")[1]), tag: .tags[0]}] | unique_by(.os)[] | [.os, .tag] | @tsv' "$metadata")

# 3. Node, pnpm and svgo, against the latest releases of the lines the
#    Dockerfile installs.
node_image="$(sed -nE 's/^FROM (node:[^ ]+) AS node-builder$/\1/p' "${dockerfile}")"
pnpm_spec="$(grep -oE 'pnpm@[0-9]+' "${dockerfile}" | head -n 1)"
sample_tag="$(jq -r 'first(.target[] | select(.target == "prod") | .tags[0])' "$metadata")"

published="$(docker run --rm --quiet --entrypoint sh "${sample_tag}" -c 'node --version; pnpm --version; svgo --version')"
latest="$(docker run --rm --quiet --pull always -e npm_config_update_notifier=false --entrypoint sh "${node_image}" -c \
    "node --version; npm view ${pnpm_spec} version --json | node -e 'const v = JSON.parse(require(\"fs\").readFileSync(0)); console.log([].concat(v).pop())'; npm view svgo version")"

if [[ "${published}" != "${latest}" ]]; then
    reasons+=("Node, pnpm or svgo: published $(tr '\n' ' ' <<< "${published}")against latest $(tr '\n' ' ' <<< "${latest}")")
fi

if [[ ${#reasons[@]} -gt 0 ]]; then
    printf 'Rebuilding every variant:\n' >&2
    printf -- '- %s\n' "${reasons[@]}" >&2
    echo "${all_variants}"
else
    echo 'Nothing changed under the production variants; rebuilding the development variants only.' >&2
    echo "${dev_variants}"
fi
