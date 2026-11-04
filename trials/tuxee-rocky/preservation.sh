#!/bin/sh
# Read-only preservation probe inside tuxee-nested; no restart or mutation.
set -eu
runtime=/workspace/tuxee-runtime
pid=$(cat "$runtime/server.pid")
kill -0 "$pid"
kill -0 21341
sha256sum "$runtime/tuxee-ubi9" /workspace/tuxee-accept/handoff.txt /workspace/tuxee-accept/gui-input.txt
curl --fail --silent http://127.0.0.1:18080/message.txt
kubectl get nodes
kubectl get pods -l app=tuxee-trial-app -o json
