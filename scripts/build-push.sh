#!/usr/bin/env bash
set -euo pipefail

TAG="${1:-v1}"
REGISTRY="${REGISTRY:-localhost:5001}"
IMAGE="${REGISTRY}/rollout-lab/app:${TAG}"

docker build --pull -t "${IMAGE}" ./app
docker push "${IMAGE}"

echo "Pushed ${IMAGE}"
