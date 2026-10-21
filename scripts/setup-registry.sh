#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-lab-cluster}"
REGISTRY_NAME="${REGISTRY_NAME:-kind-registry}"
HOST_PORT="${HOST_PORT:-5001}"

command -v docker >/dev/null
command -v kind >/dev/null

if ! docker inspect "${REGISTRY_NAME}" >/dev/null 2>&1; then
  docker run -d --restart=always \
    -p "127.0.0.1:${HOST_PORT}:5000" \
    --name "${REGISTRY_NAME}" \
    registry:2
else
  echo "Registry container ${REGISTRY_NAME} already exists."
fi

if ! docker network inspect kind >/dev/null 2>&1; then
  echo "Docker network 'kind' not found. Is the kind cluster running?"
  exit 1
fi

if ! docker network inspect kind --format '{{json .Containers}}' | grep -q "${REGISTRY_NAME}"; then
  docker network connect kind "${REGISTRY_NAME}" || true
fi

mapfile -t nodes < <(kind get nodes --name "${CLUSTER_NAME}")
if ((${#nodes[@]} == 0)); then
  echo "No nodes found for kind cluster '${CLUSTER_NAME}'."
  exit 1
fi

for node in "${nodes[@]}"; do
  echo "Configuring registry mirror on ${node}"
  docker exec "${node}" mkdir -p /etc/containerd/certs.d/localhost:5001
  docker exec -i "${node}" sh -c 'cat > /etc/containerd/certs.d/localhost:5001/hosts.toml' <<'EOF'
[host."http://kind-registry:5000"]
  capabilities = ["pull", "resolve"]
EOF
done

echo
echo "Registry endpoint: http://127.0.0.1:${HOST_PORT}"
echo "Image references inside Kubernetes: localhost:${HOST_PORT}/rollout-lab/app:<tag>"
echo "If pulls fail, verify containerd uses /etc/containerd/certs.d as its registry config_path."
