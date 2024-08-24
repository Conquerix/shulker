{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.shulker.modules.netbird.server;
in
{
  options.shulker.modules.netbird.server = {
    enable = mkEnableOption "Enable netbird server service";
    baseUrl = mkOption {
      type = types.str;
      default = "example.com";
      description = "Default url where netbird will be accessible.";
    };
    subDomain = mkOption {
      type = types.str;
      default = "netbird";
      description = "Default subdomain where netbird will be accessible.";
    };
    stateDir = mkOption {
      type = types.str;
      default = "/var/lib/netbird";
      description = "State Directory.";
    };
  };

  config = mkIf cfg.enable {

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ 80 443 ];
    };

    services.netbird.server = {
      enable = true;

      domain = "${cfg.subDomain}.${cfg.baseUrl}";

      coturn = {
        enable = true;

        passwordFile = "/secret/netbird-coturn-secret";
      };

      management = {
        oidcConfigEndpoint = "https://auth.shulker.fr/application/o/netbird/.well-known/openid-configuration";

        settings = {
          TURNConfig = {
            Turns = [
              {
                Proto = "udp";
                URI = "turn:${cfg.subDomain}.${cfg.baseUrl}:3478";
                Username = "netbird";
                Password._secret = "/secret/netbird-turn-secret";
              }
            ];
          };
        };
      };
    };

    services.nginx = {
      enable = true;
      virtualHosts."netbird" = {
        serverName = "${cfg.subDomain}.${cfg.baseUrl}";
        forceSSL = true;
        useACMEHost = cfg.baseUrl;
        locations = {
          "/" = {
            root = cfg.finalDrv;
            tryFiles = "$uri $uri.html $uri/ =404";
          };

          "/404.html".extraConfig = ''
            internal;
          '';

          "/api".proxyPass = "http://localhost:${builtins.toString cfg.port}";

          "/management.ManagementService/".extraConfig = ''
            # This is necessary so that grpc connections do not get closed early
            # see https://stackoverflow.com/a/67805465
            client_body_timeout 1d;

            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass grpc://localhost:${builtins.toString cfg.port};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';

          "/signalexchange.SignalExchange/".extraConfig = ''
            # This is necessary so that grpc connections do not get closed early
            # see https://stackoverflow.com/a/67805465
            client_body_timeout 1d;

            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass grpc://localhost:${builtins.toString cfg.port};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';
        };
      };
    };

    opsm.secrets = {
      authentik-netbird-client-id.secretRef = "op://Shulker/${config.networking.hostName}/Authentik Netbird Client ID";
      authentik-netbird-svc-password.secretRef = "op://Shulker/${config.networking.hostName}/Authentik Nebird svc password | ID: Netbird";
      netbird-coturn-secret.secretRef = "op://Shulker/${config.networking.hostName}/Netbird Coturn Secret";
      netbird-turn-secret.secretRef = "op://Shulker/${config.networking.hostName}/Netbird Turn Secret";
    };
  };
}
