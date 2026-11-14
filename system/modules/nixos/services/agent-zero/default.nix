{ config, lib, pkgs, ... }:
let
  cfg = config.shulker.system.modules.agent-zero;
  state = "/var/lib/aegis-agent-zero";
  bootstrap = pkgs.writeText "aegis-model-presets.yaml" ''
    - name: Default
      chat:
        provider: openai
        name: cx/gpt-6.1-sol
        api_base: http://omniroute:20128/v1
        ctx_length: 200000
        ctx_history: 0.7
        vision: true
        kwargs:
          a0_api_mode: responses
      utility:
        provider: openai
        name: cx/gpt-6.1-sol
        api_base: http://omniroute:20128/v1
        ctx_length: 200000
        ctx_input: 0.7
        kwargs:
          a0_api_mode: responses
      embedding:
        provider: huggingface
        name: sentence-transformers/all-MiniLM-L6-v2
  '';
in {
  options.shulker.system.modules.agent-zero.enable = lib.mkEnableOption "Aegis Agent Zero trial";
  config = lib.mkIf cfg.enable {
    shulker.system.modules.containers.enable = true;
    services.onepassword-secrets.secrets.aegisA0Inference = {
      reference = "op://Shulker/le2st2tuezt3cucmujhezbjwwu/aegisOmnirouteKey";
      mode = "0400"; services = [ "docker-aegis-agent-zero" ];
    };
    environment.persistence."/nix/persist".directories = [{ directory = state; mode = "0700"; user = "root"; group = "root"; }];
    shulker.system.modules.backup.dirs = [ state ];
    virtualisation.oci-containers.containers.aegis-agent-zero = {
      image = "docker.io/agent0ai/agent-zero:v2.15@sha256:05d6ab347bd7db4b6bd5a7d902c9965281ff852ff23f29fffcc1c8919e628bd8";
      pull = "missing";
      ports = [ "127.0.0.1:23252:80" ];
      volumes = [ "${state}/usr:/a0/usr:rw" ];
      environment = { AUTH_LOGIN = ""; AUTH_PASSWORD = ""; };
      extraOptions = [ "--network=omniroute" "--memory=12g" "--cpus=4" "--pids-limit=2048" "--shm-size=1g" "--ulimit=nofile=65535:65535" ];
    };
    systemd.services.docker-aegis-agent-zero = {
      requires = [ "opnix-secrets.service" "docker-network-omniroute.service" ];
      after = [ "opnix-secrets.service" "docker-network-omniroute.service" ];
      unitConfig.RequiresMountsFor = [ state ];
      preStart = ''
        install -d -m 0700 ${state}/usr/plugins/_model_config
        if [ ! -e ${state}/usr/plugins/_model_config/presets.yaml ]; then
          install -m 0600 ${bootstrap} ${state}/usr/plugins/_model_config/presets.yaml
          printf '%s\n' '{"model_preset":"Default"}' > ${state}/usr/plugins/_model_config/config.json
        fi
        ${pkgs.python3}/bin/python3 ${./render-secret.py} ${config.services.onepassword-secrets.secrets.aegisA0Inference.path} ${state}/usr/.env
      '';
    };
    services.newt.blueprint.public-resources.aegis = {
      name = "Aegis"; mode = "http"; full-domain = "aegis.shulker.link"; ssl = true;
      auth = { sso-enabled = true; sso-users = [ "conquerix@shulker.link" ]; sso-roles = [ ]; whitelist-users = [ ]; };
      targets = [{ hostname = "127.0.0.1"; port = 23252; method = "http"; }];
    };
  };
}
