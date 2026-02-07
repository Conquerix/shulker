{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.shulker.system.modules.yubikey;
in
{
  options.shulker.system.modules.yubikey = {
    enable = mkEnableOption "yubikey support";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      yubikey-personalization
      yubikey-manager
      opensc
    ];

    security.pam.yubico = {
      enable = true;
      debug = false;
      mode = "challenge-response";
    };

    programs.gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    #programs.ssh.startAgent = true;

    programs.ssh.agentPKCS11Whitelist = "${pkgs.opensc}/lib/opensc-pkcs11.so";

    services = {
      # Required for gpg smartcard (yubikey) to work
      pcscd.enable = true;
      # Required for Yubikey device to work
      udev.packages = with pkgs; [
        yubikey-personalization
        libu2f-host
      ];
    };
  };
}
