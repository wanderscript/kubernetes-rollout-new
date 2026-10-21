#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl apply -f "${ROOT}/manifests/00-namespace.yaml"
kubectl apply -f "${ROOT}/manifests/01-secret.yaml"
kubectl apply -f "${ROOT}/manifests/10-deployment.yaml"
kubectl -n rollout-lab rollout status deployment/rollout-lab --timeout=180s
kubectl -n rollout-lab get deploy,rs,pods,svc,pdb -o wide
