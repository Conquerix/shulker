{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules;
in
{
  options.shulker.modules.ssh_server = {
    enable = mkEnableOption "Enable openssh daemon";

    tor = {
      enable = mkEnableOption "Enable tor service for reliable ssh access";

      port = mkOption {
      	type = types.port;
      	default = 22;
      	description = "Default port to open to tor. Changing it is highly recommended !";
      };
    };
  };

  config = mkIf cfg.ssh_server.enable {

  services.openssh = {
    enable = true;
    #settings.PasswordAuthentication = false;
    #settings.KbdInteractiveAuthentication = false;
    openFirewall = true;
    hostKeys = [
      {
        bits = 4096;
        path = "/nix/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
      }
      {
        path = "/nix/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  environment = mkIf (cfg.impermanence.enable) {

    persistence."/nix/persist".files = [
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      (mkIf (cfg.ssh_server.tor.enable){
          file = "/run/keys/tor/ssh_access/hs_ed25519_secret_key";
          parentDirectory = {
          	user = "tor";
          	group = "tor";
          	mode = "u=rw,g=,o=";
          };
        })
      ];
    };

  services.tor = mkIf (cfg.ssh_server.tor.enable) {
    enable = true;
    enableGeoIP = false;
    relay.onionServices = {
      ssh_access = {
        version = 3;
        secretKey = "/run/keys/tor/ssh_access/hs_ed25519_secret_key";
        path = "/var/lib/tor/onion/ssh_access";
        map = [{
          port = cfg.ssh_server.tor.port;
          target = {
            addr = "127.0.0.1";
            port = 22;
          };
        }];
      };
    };
    settings = {
      ClientUseIPv4 = true;
      ClientUseIPv6 = false;
      ClientPreferIPv6ORPort = false;
      };
    };
  };
}
