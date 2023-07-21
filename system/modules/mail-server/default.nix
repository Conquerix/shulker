{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.mail-server;
in
{
  options.shulker.modules.mail-server = {
    enable = mkEnableOption "Enable mail-server module";

    tor = {
      enable = mkEnableOption "Enable tor service for reliable ssh access";

      port = mkOption {
      	type = types.port;
      	default = 22;
      	description = "Default port to open to tor. Changing it is highly recommended !";
      };
    };
  };

  config = mkIf cfg.enable {
    mailserver = {
      enable = true;
      fqdn = "mail.shulker.fr";
      domains = [ "shulker.fr" ];
  
      # A list of all login accounts. To create the password hashes, use
      # nix-shell -p mkpasswd --run 'mkpasswd -sm bcrypt'
      loginAccounts = {
        "admin@shulker.fr" = {
          hashedPasswordFile = "./admin.secrets";
          aliases = ["admin@shulker.fr"];
        };
        #"user2@example.com" = { ... };
      };
  
      # Use Let's Encrypt certificates. Note that this needs to set up a stripped
      # down nginx and opens port 80.
      certificateScheme = 3;
    };
  };
}
