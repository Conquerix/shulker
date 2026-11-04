#!/bin/bash
set -euo pipefail
podman build -t "$EXPECTED_REF" -f Dockerfile .
rm -f -- /workspace/app-image.tar
podman save --format docker-archive -o /workspace/app-image.tar "$EXPECTED_REF"
podman exec -i tuxee-trial-control-plane ctr --namespace=k8s.io images import --local --all-platforms --digests --snapshotter=fuse-overlayfs - < /workspace/app-image.tar
