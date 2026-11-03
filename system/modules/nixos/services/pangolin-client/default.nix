# Dedicated machine client; Newt remains the independent site connector.
{ config, lib, pkgs, ... }:
let
  cfg = config.shulker.system.modules.pangolin-client;
  client = pkgs.stdenvNoCC.mkDerivation {
    pname = "pangolin-cli";
    version = "0.19.1";
    src = pkgs.fetchurl {
      url = "https://github.com/fosrl/cli/releases/download/0.19.1/pangolin-cli_linux_amd64";
      sha256 = "8ee5d1a2f2d33f8e62b81349b7bea36b9f08b8e76f30a09767c04ce9ccbc0a3d";
    };
    dontUnpack = true;
    installPhase = ''
      install -Dm755 "$src" "$out/bin/pangolin"
    '';
    meta.platforms = [ "x86_64-linux" ];
  };
in
{
  options.shulker.system.modules.pangolin-client = {
    enable = lib.mkEnableOption "dedicated Overseer Pangolin machine client";
  };
  config = lib.mkIf cfg.enable {
    services.onepassword-secrets.secrets.overseerPangolinClientEnv = {
      reference = "op://Shulker/j3ucxj57rqa4cpslcafgze4nxq/Pangolin/Client environment";
      mode = "0600";
      services = [ "pangolin-overseer" ];
    };
    shulker.system.secretPreflight.schemas.overseerPangolinClientEnv = {
      format = "dotenv";
      exactKeys = {
        PANGOLIN_CLIENT_ID = { minLength = 15; pattern = "^[a-z0-9]+$"; };
        PANGOLIN_CLIENT_SECRET = { minLength = 48; pattern = "^[a-z0-9]+$"; };
      };
    };
    systemd.services.pangolin-overseer = {
      description = "Overseer private SSH Pangolin client";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "opnix-secrets.service" ];
      wants = [ "network-online.target" ];
      requires = [ "opnix-secrets.service" ];
      environment = {
        HOME = "/var/lib/pangolin-overseer";
        XDG_CONFIG_HOME = "/var/lib/pangolin-overseer/.config";
        PANGOLIN_ENDPOINT = "https://proxy.shulker.link";
      };
      path = [ pkgs.iproute2 ];
      serviceConfig = {
        Type = "simple";
        User = "root";
        EnvironmentFile = config.services.onepassword-secrets.secrets.overseerPangolinClientEnv.path;
        ExecStart = "${client}/bin/pangolin up --attach --override-dns=false --interface-name=overseer-pango --http-addr=127.0.0.1:21820";
        Restart = "always";
        RestartSec = "10s";
        StateDirectory = "pangolin-overseer";
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        DevicePolicy = "closed";
        DeviceAllow = [ "/dev/net/tun rw" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
      };
    };
    environment.persistence."/nix/persist".directories = [
      { directory = "/var/lib/pangolin-overseer"; mode = "0700"; }
    ];
  };
}
