# Disposable Rocky 9 / Tuxee qualification harness

This explicit opt-in NixOS module declares a temporary Enderdragon QEMU/KVM
service. It is **not** a proposed VM-based final workspace architecture.
It is not imported by a host and never starts at boot. No firewall, authorized
keys, host engine sockets or production services are changed by the module.

## Resources and preparation

- Four vCPUs, 8 GiB guest memory, 10 GiB service memory ceiling.
- Private state directory `/nix/persist/tuxee-rocky-trial`, mode 0700.
- Sparse 50 GiB overlay; downloaded base image retained in the Nix store.
- Rocky 9.8 GenericCloud Base 20260525.0, SHA256 pinned from its official
  [checksum](https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2.CHECKSUM).
- QEMU user networking; guest SSH bound only to host `127.0.0.1:22229`.
- Provide `seed.iso` (cloud-init NoCloud) privately before explicit service
  start. Create only a dedicated trial user with its trial SSH public key;
  disable password authentication, keep SELinux enforcing, and do not embed
  private keys or production credentials in cloud-init. No seed is committed.
- Console output belongs to the private state directory. Treat it as private
  because cloud-init may log provisioning details.

## Deployment gate

Import `../../../../trials/tuxee-rocky/harness.nix` from the Enderdragon host
entry in a dedicated candidate checkout. Track the module for Git-flake
inclusion. Follow the repository checked-build/dry-activate/test/switch flow.
Review **all** proposed restarts before activation; trial authorization does
not authorize unrelated Home Manager or secret-dependent service restarts.
Do not work around this gate by installing generated units imperatively or
pinning unrelated service definitions.

Run `bash tests/tuxee-rocky-trial.sh` for the minimal static guard. It does not
prove runtime operation. After activation, explicitly start
`tuxee-rocky-trial.service`, verify loopback binding and guest identity, and
record versions and SELinux state before installing guest dependencies.

## Required runtime evidence (not yet obtained)

The decisive chain is rootless guest-host Podman → UBI9 Init/systemd →
container-root inner Podman → kind/containerd → real Kubernetes workload.
Start with bounded launch capabilities, not blanket `--privileged`; record
any required seccomp/SELinux/capability exceptions. Do not mount a host engine
socket. Exercise Tilt image build, deploy, live update and port forwarding;
then investigate target-compatible Tuxee build, SSH same-file editor handoff,
actual authorized subscription-backed agent execution, representative GUI,
repository inventory, persistence and restart/shutdown. Rocky is representative
EL9 evidence, not final RHEL validation. Missing runtime evidence is a gap,
not success inferred from Nix evaluation.

## Teardown

Stop only `tuxee-rocky-trial.service`; verify it is inactive and port 22229 has
no listener. Remove the explicit trial import using the checked deployment
flow, with the same unrelated-change gate. Retain logs and the stopped disk
when evidence is useful; deletion must name this trial's owned directory and
must not touch unrelated VM data. The module does not automatically delete
its disk, seed, console, logs or source checkout.

## First preparation result

The candidate host system built and all-system flake evaluation passed. The
checked dry activation requested `home-manager-conquerix.service` restart;
its registry points at the copied flake source, while the live registry points
at the live source. Activation was **not attempted**: this is outside the
trial-only interruption scope. The VM has not booted and no nested-runtime
claim is made. Full evidence and exact host paths are retained privately in
`/workspace/knowledge/tuxee/rocky-trial-preparation.md` by the trial operator.
