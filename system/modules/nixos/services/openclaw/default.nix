# Aegis: independently owned native-app Gateway with declarative lifecycle.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.shulker.system.modules.openclaw;
  state = "/var/lib/aegis";
  package = inputs.openclaw.packages.${pkgs.stdenv.hostPlatform.system}.openclaw-gateway;
  secret = name: config.services.onepassword-secrets.secrets.${name}.path;
  configuration = pkgs.writeText "aegis-openclaw.json" (builtins.toJSON {
    gateway = {
      mode = "local";
      bind = "loopback";
      port = 23251;
      publicOrigin = "https://aegis.shulker.link";
      auth = { mode = "token"; token = { source = "env"; provider = "default"; id = "OPENCLAW_GATEWAY_TOKEN"; }; };
      trustedProxies = [ "127.0.0.1" "::1" ];
      nodes = {
        pairing = { autoApproveLocal = false; sshVerify = false; };
        commands.deny = [ "system.run" "screen.record" "screen.snapshot" "camera.snap" "camera.clip" "location.get" "desktop.stream" ];
      };
      terminal.enabled = false;
    };
    agents = {
      defaults = {
        workspace = "${state}/workspace";
        model = { primary = "omniroute/cx/gpt-6.1-sol"; fallbacks = [ ]; };
        utilityModel = "";
        maxConcurrent = 2;
        elevatedDefault = "off";
        heartbeat.every = "0m";
      };
      entries.aegis = { name = "Aegis"; identity.name = "Aegis"; };
    };
    models = {
      mode = "replace";
      providers.omniroute = {
        baseUrl = "http://127.0.0.1:23250/v1";
        api = "openai-completions";
        apiKey = { source = "env"; provider = "default"; id = "AEGIS_OMNIROUTE_API_KEY"; };
        models = [{ id = "cx/gpt-6.1-sol"; name = "GPT 6.1 Sol via OmniRoute"; reasoning = true; input = [ "text" "image" ]; contextWindow = 200000; maxTokens = 16384; }];
      };
    };
    plugins.entries.memory-core.config.dreaming.enabled = false;
    tools = { exec.mode = "ask"; elevated.enabled = false; };
    discovery.mdns.mode = "off";
    update.checkOnStart = false;
  });
  prepare = pkgs.writeShellScript "aegis-prepare" ''
    set -eu
    install -d -m 0700 -o aegis -g aegis ${state}/workspace
    umask 077
    ${pkgs.python3}/bin/python3 ${./render-environment.py} \
      ${secret "aegisGatewayToken"} ${secret "aegisInferenceKey"} ${secret "aegisServiceAccount"} /run/aegis/environment
    if [ ! -e ${state}/workspace/AGENTS.md ]; then
      install -m 0600 -o aegis -g aegis ${./AGENTS.md} ${state}/workspace/AGENTS.md
    fi
  '';
in {
  options.shulker.system.modules.openclaw = {
    enable = lib.mkEnableOption "Aegis OpenClaw Gateway";
    paused = lib.mkEnableOption "retain OpenClaw state and secrets without running its Gateway or declaring ingress";
  };
  config = lib.mkIf cfg.enable {
    users.groups.aegis = { };
    users.users.aegis = { isSystemUser = true; group = "aegis"; home = state; createHome = true; };
    services.onepassword-secrets.secrets = {
      aegisGatewayToken = { reference = "op://Shulker/le2st2tuezt3cucmujhezbjwwu/aegisGatewayToken"; mode = "0400"; services = [ "aegis" ]; };
      aegisInferenceKey = { reference = "op://Shulker/le2st2tuezt3cucmujhezbjwwu/aegisOmnirouteKey"; mode = "0400"; services = [ "aegis" ]; };
      aegisServiceAccount = { reference = "op://Shulker/le2st2tuezt3cucmujhezbjwwu/yoil2ium4cr6epr2u3wju66pfa"; mode = "0400"; services = [ "aegis" ]; };
    };
    environment.persistence."/nix/persist".directories = [{ directory = state; user = "aegis"; group = "aegis"; mode = "0700"; }];
    shulker.system.modules.backup.dirs = [ state ];
    systemd.services.aegis = {
      description = "Aegis OpenClaw Administrator";
      wantedBy = lib.optionals (!cfg.paused) [ "multi-user.target" ];
      unitConfig.ConditionPathExists = lib.optionalString cfg.paused "/run/aegis-resume-explicitly-required";
      wants = [ "network-online.target" ];
      requires = [ "opnix-secrets.service" ];
      after = [ "network-online.target" "opnix-secrets.service" "docker-omniroute.service" ];
      unitConfig.RequiresMountsFor = [ state ];
      environment = { HOME = state; OPENCLAW_STATE_DIR = state; OPENCLAW_CONFIG_PATH = toString configuration; OPENCLAW_NIX_MODE = "1"; };
      path = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.curl pkgs.jq pkgs.python3 pkgs.openssh pkgs._1password-cli ];
      serviceConfig = {
        User = "aegis"; Group = "aegis";
        RuntimeDirectory = "aegis"; RuntimeDirectoryMode = "0700";
        ExecStartPre = "+${prepare}";
        EnvironmentFile = "-/run/aegis/environment";
        ExecStart = "${package}/bin/openclaw gateway run";
        WorkingDirectory = state;
        Restart = "on-failure"; RestartSec = 5;
        UMask = "0077";
        NoNewPrivileges = true; PrivateTmp = true; ProtectSystem = "strict"; ProtectHome = true;
        ReadWritePaths = [ state "/run/aegis" ];
        InaccessiblePaths = [ "/var/lib/hermes-administrator" "/var/lib/omniroute" "/etc/opnix-token" ];
      };
    };
    services.newt.blueprint.public-resources.aegis = lib.mkIf (!cfg.paused) {
      name = "Aegis"; mode = "http"; full-domain = "aegis.shulker.link"; ssl = true;
      # Native Gateway auth + explicit device pairing, not browser SSO redirects.
      auth = { sso-enabled = false; sso-users = [ ]; sso-roles = [ ]; whitelist-users = [ ]; };
      targets = [{ hostname = "127.0.0.1"; port = 23251; method = "http"; }];
    };
  };
}
