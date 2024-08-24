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
    mgmtPort = mkOption {
      type = types.port;
      default = 8011;
      description = "Default internal port to open netbird management.";
    };
    signalPort = mkOption {
      type = types.port;
      default = 8012;
      description = "Default internal port to open netbird signal.";
    };
    clientID = mkOption {
      type = types.str;
      description = "Auth client ID of netbird";
    };
    authBaseUrl = mkOption {
      type = types.str;
      description = "Auth BaseUrl of netbird";
    };
    oidcConfigEndpoint = mkOption {
      type = types.str;
      description = "OIDC Config endpoint for netbird";
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

        passwordFile = "/secrets/netbird-coturn-secret";
      };

      dashboard.settings = {
        AUTH_CLIENT_ID = cfg.clientID;
        AUTH_AUTHORITY = "${cfg.authBaseUrl}/netbird/";
      };

      signal.port = cfg.signalPort;

      management = {
        oidcConfigEndpoint = cfg.oidcConfigEndpoint;
        port = cfg.mgmtPort;

        settings = {
          HttpConfig = {
            Address = "0.0.0.0:${builtins.toString cfg.mgmtPort}";
            AuthIssuer = "${cfg.authBaseUrl}/netbird/";
            AuthAudience = cfg.clientID;
          };
          TURNConfig = {
            Turns = [
              {
                Proto = "udp";
                URI = "turn:${cfg.subDomain}.${cfg.baseUrl}:3478";
                Username = "netbird";
                Password._secret = "/secrets/netbird-coturn-secret";
              }
            ];
          };
          DataStoreEncryptionKey._secret = "/secrets/netbird-datastore-key";
          IdpManagerConfig = {
            ManagerType = "authentik";
            ClientConfig = {
              Issuer = "${cfg.authBaseUrl}/netbird/";
              TokenEndpoint = "${cfg.authBaseUrl}/token/";
              ClientID = cfg.clientID;
              GrantType = "client_credentials";
            };
            ExtraConfig = {
              Username = "netbird";
              Password._secret = "/secrets/authentik-netbird-svc-password";
            };
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
            root = config.services.netbird.server.dashboard.finalDrv;
            tryFiles = "$uri $uri.html $uri/ =404";
          };

          "/404.html".extraConfig = ''
            internal;
          '';

          "/api".proxyPass = "http://localhost:${builtins.toString cfg.mgmtPort}";

          "/management.ManagementService/".extraConfig = ''
            # This is necessary so that grpc connections do not get closed early
            # see https://stackoverflow.com/a/67805465
            client_body_timeout 1d;

            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass grpc://localhost:${builtins.toString cfg.mgmtPort};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';

          "/signalexchange.SignalExchange/".extraConfig = ''
            # This is necessary so that grpc connections do not get closed early
            # see https://stackoverflow.com/a/67805465
            client_body_timeout 1d;

            grpc_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            grpc_pass grpc://localhost:${builtins.toString cfg.signalPort};
            grpc_read_timeout 1d;
            grpc_send_timeout 1d;
            grpc_socket_keepalive on;
          '';
        };
      };
    };

    opsm.secrets = {
      authentik-netbird-client-id.secretRef = "op://Shulker/${config.networking.hostName}/Authentik Netbird Client ID";
      authentik-netbird-svc-password.secretRef = "op://Shulker/${config.networking.hostName}/Authentik Netbird svc password";
      netbird-coturn-secret = {
        secretRef = "op://Shulker/${config.networking.hostName}/Netbird Coturn Secret";
        user = "turnserver";
        mode = "600";
      };
      netbird-datastore-key.secretRef = "op://Shulker/${config.networking.hostName}/Netbird Datastore Key";
    };
  };
}
