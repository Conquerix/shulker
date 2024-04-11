{ config, inputs, lib, name, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.yubikey;
in
{
  options.shulker.modules.yubikey = {
    enable = mkEnableOption "yubikey support";
    istty = mkEnableOption "Set pinentry to curses if no display";
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
      enableSSHSupport = false;
      #pinentryPackage = if cfg.istty then "curses" else "qt";
    };

    programs.ssh.startAgent = true;

    programs.ssh.agentPKCS11Whitelist = "${pkgs.opensc}/lib/opensc-pkcs11.so";
    
    services = {
      # Required for gpg smartcard (yubikey) to work
      pcscd.enable = true;
      # Required for Yubikey device to work
      udev.packages = with pkgs; [ yubikey-personalization libu2f-host ];
    };
  };
}
