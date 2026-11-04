# Disposable test harness: import explicitly on Enderdragon only for a trial.
{ pkgs, ... }:
let
  state = "/nix/persist/tuxee-rocky-trial";
  image = pkgs.fetchurl {
    url = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base-9.8-20260525.0.x86_64.qcow2";
    sha256 = "92c206cc6f790c61583247eefe87890f8828420662c17cacf247cec78ab4eec8";
  };
in
{
  systemd.services.tuxee-rocky-trial = {
    description = "Disposable Rocky 9 nested Podman qualification VM";
    # Intentionally no boot target: start and stop explicitly.
    serviceConfig = {
      Type = "simple";
      Restart = "no";
      UMask = "0077";
      MemoryMax = "10G";
      CPUQuota = "400%";
      TimeoutStopSec = 60;
      KillSignal = "SIGTERM";
      WorkingDirectory = state;
      ExecStart = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 8192 -display none -serial file:${state}/console.log -monitor none -drive file=${state}/root.qcow2,format=qcow2,if=virtio -drive file=${state}/seed.iso,format=raw,media=cdrom,readonly=on -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22229-:22 -device virtio-net-pci,netdev=net0 -no-reboot";
    };
    preStart = ''
      test -f ${state}/seed.iso
      if ! test -f ${state}/root.qcow2; then
        ${pkgs.qemu_kvm}/bin/qemu-img create -f qcow2 -F qcow2 -b ${image} ${state}/root.qcow2 50G
      fi
    '';
  };
}
