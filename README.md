# Kubernetes Rollout Lab (Go + kind + local registry)

This lab demonstrates Deployment rolling updates, readiness gating, failed rollouts, rollback, graceful shutdown, and continuous HTTP traffic measurement.

> Lab only: the admin endpoints are protected by a token, but the token in `manifests/01-secret.yaml` is a local placeholder. Do not reuse it or expose this Service outside the lab.

## Assumptions

- Existing kind cluster named `lab-cluster`.
- Docker Engine, `kind`, `kubectl`, Go-compatible Docker build, Python 3.
- Run commands from this directory unless shown otherwise.
- The PostgreSQL Helm chart is not modified.

## 1. Configure a local registry

```bash
chmod +x scripts/*.sh
./scripts/setup-registry.sh
```

This creates (or reuses) a `registry:2` container published on `127.0.0.1:5001`, connects it to Docker's `kind` network, and configures each kind node's containerd registry host mapping.

If your cluster has another name:

```bash
CLUSTER_NAME=your-kind-cluster ./scripts/setup-registry.sh
```

Check the registry from the host:

```bash
curl -fsS http://127.0.0.1:5001/v2/
```

Expected response: `{}`.

## 2. Build and push v1

```bash
./scripts/build-push.sh v1
```

## 3. Deploy

```bash
./scripts/deploy.sh
kubectl -n rollout-lab port-forward svc/rollout-lab 18080:80
```

Keep port-forward running. In another terminal:

```bash
curl -i http://127.0.0.1:18080/
curl -i http://127.0.0.1:18080/health/live
curl -i http://127.0.0.1:18080/health/ready
curl -s http://127.0.0.1:18080/metrics
```

## 4. Run continuous traffic

Requires Python 3 only; no third-party packages:

```bash
python3 scripts/load-test.py --url http://127.0.0.1:18080/ --duration 180 --concurrency 10
```

While the test is running, deploy v2 from another terminal.

## 5. Deploy v2

```bash
./scripts/build-push.sh v2
kubectl -n rollout-lab set image deployment/rollout-lab app=localhost:5001/rollout-lab/app:v2
kubectl -n rollout-lab set env deployment/rollout-lab APP_VERSION=v2
kubectl -n rollout-lab rollout status deployment/rollout-lab --timeout=180s
kubectl -n rollout-lab rollout history deployment/rollout-lab
kubectl -n rollout-lab get pods -o wide
```

The image tag and `APP_VERSION` are changed in separate commands; both trigger Pod template changes. For a cleaner single revision, update `image` and `APP_VERSION` together in `manifests/10-deployment.yaml`, then run `kubectl apply -f manifests/10-deployment.yaml`.

For v3, repeat with `./scripts/build-push.sh v3` and update the manifest to tag/version `v3`.

## 6. Simulate a readiness failure

First identify one Pod and its name:

```bash
kubectl -n rollout-lab get pods -l app.kubernetes.io/name=rollout-lab
```

Use port-forward to a specific Pod in a separate terminal, then use the admin endpoint to change its readiness. For example:

```bash
kubectl -n rollout-lab port-forward pod/<POD_NAME> 18081:8080
```

In another terminal:

```bash
curl -i -X POST \
  -H 'X-Lab-Token: local-lab-only-change-me' \
  'http://127.0.0.1:18081/admin/ready?value=false'
curl -i http://127.0.0.1:18081/health/ready
```

Expected: admin request returns 200; readiness returns 503. Restore it:

```bash
curl -i -X POST \
  -H 'X-Lab-Token: local-lab-only-change-me' \
  'http://127.0.0.1:18081/admin/ready?value=true'
```

A Pod's readiness failure removes it from eligible Service endpoints, but does not restart the container. A liveness failure can restart it.

## 7. Simulate a failed rollout safely

Build and push a deliberately nonexistent tag is not required; a nonexistent image can test image-pull failure:

```bash
kubectl -n rollout-lab set image deployment/rollout-lab app=localhost:5001/rollout-lab/app:does-not-exist
kubectl -n rollout-lab rollout status deployment/rollout-lab --timeout=30s
kubectl -n rollout-lab describe deployment rollout-lab
kubectl -n rollout-lab get rs,pods
kubectl -n rollout-lab get events --sort-by=.metadata.creationTimestamp
```

With `maxUnavailable: 0`, the rollout should retain available old replicas while the new ReplicaSet cannot become available, subject to cluster capacity and other failures.

Rollback:

```bash
kubectl -n rollout-lab rollout undo deployment/rollout-lab
kubectl -n rollout-lab rollout status deployment/rollout-lab --timeout=180s
kubectl -n rollout-lab get pods
curl -i http://127.0.0.1:18080/
```

## 8. Observe graceful shutdown

```bash
kubectl -n rollout-lab logs deployment/rollout-lab --since=10m
kubectl -n rollout-lab get pods -w
kubectl -n rollout-lab get endpointslice -l kubernetes.io/service-name=rollout-lab -w
```

The `preStop` hook sleeps for five seconds to allow endpoint propagation, then Kubernetes sends SIGTERM. The Go process marks itself unready and calls `http.Server.Shutdown`. This is a demonstration, not a universal zero-downtime guarantee.

## Acceptance criteria

1. Deployment converges to 3/3 available replicas.
2. `/health/live` and `/health/ready` return 200 for healthy Pods.
3. Load test runs during v1→v2 and reports no transport errors or HTTP 5xx.
4. Failed image rollout does not intentionally remove healthy old replicas.
5. Rollback returns the Deployment to a valid image and 3/3 availability.
6. Evidence is collected from `rollout status`, `rollout history`, `describe`, events, Pods, EndpointSlices, and load-test output.
7. Explain why a PDB is not a substitute for Deployment rollout settings and why probes alone cannot guarantee end-to-end availability.

## Troubleshooting

- Registry push fails: `docker ps --filter name=kind-registry` and `curl -v http://127.0.0.1:5001/v2/`.
- Image pull fails: inspect `kubectl -n rollout-lab describe pod <pod>` and verify `/etc/containerd/certs.d/localhost:5001/hosts.toml` exists on every kind node.
- `ImagePullBackOff`: confirm the tag exists with `curl -fsS http://127.0.0.1:5001/v2/_catalog`.
- Port-forward is not listening: ensure the command is still running and use `kubectl -n rollout-lab get svc`.
- Insufficient capacity: inspect Pod events and node allocatable resources; `maxSurge: 1` requires capacity for one additional Pod during a rollout.
