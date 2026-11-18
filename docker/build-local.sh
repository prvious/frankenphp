#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

sources="$(docker buildx bake --print local-dev | bash docker/resolve-sources.sh)"
docker buildx bake -f docker-bake.hcl -f - local-dev <<< "$sources"
