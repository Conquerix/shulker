{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
with lib;
let
  passwordHashSources = config.shulker.system.security.passwordHashSources;
  runtimePasswordDirectory = "/run/password-hashes";
in
{
  options.shulker.system.security.passwordHashSources = mkOption {
    type = types.attrsOf types.str;
    default = { };
    description = ''
      External password hash files to validate before immutable users are
      updated. Invalid or missing hashes lock the corresponding password.
    '';
  };

  config = {

    users.mutableUsers = false;

    system.activationScripts.preparePasswordHashes = {
      deps = [ "etc" ];
      text = ''
        ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${runtimePasswordDirectory}

        prepare_password_hash() {
          source="$1"
          target="$2"
          account="$3"
          valid=true

          if [ ! -f "$source" ] || [ ! -s "$source" ]; then
            valid=false
          fi
          if [ "$valid" = true ] && [ "$(${pkgs.coreutils}/bin/stat -c %u "$source")" != 0 ]; then
            valid=false
          fi
          if [ "$valid" = true ] && [ "$(${pkgs.coreutils}/bin/stat -c %g "$source")" != 0 ]; then
            valid=false
          fi
          if [ "$valid" = true ] && [ "$(${pkgs.coreutils}/bin/stat -c %a "$source")" != 600 ]; then
            valid=false
          fi
          if [ "$valid" = true ] && [ "$(${pkgs.coreutils}/bin/wc -l < "$source")" -ne 1 ]; then
            valid=false
          fi
          if [ "$valid" = true ] && ! ${pkgs.gnugrep}/bin/grep -Eq '^\$(y|6)\$[^:[:space:]]+$' "$source"; then
            valid=false
          fi

          if [ "$valid" = true ]; then
            ${pkgs.coreutils}/bin/install -m 0600 -o root -g root "$source" "$target"
          else
            echo "WARNING: invalid or missing password hash for $account at $source; password login is locked" >&2
            printf '!\n' | ${pkgs.coreutils}/bin/install -m 0600 -o root -g root /dev/stdin "$target"
          fi
        }

        ${concatStringsSep "\n" (
          mapAttrsToList (
            account: source:
            "prepare_password_hash ${escapeShellArg source} ${escapeShellArg "${runtimePasswordDirectory}/${account}"} ${escapeShellArg account}"
          ) passwordHashSources
        )}
      '';
    };
    system.activationScripts.users.deps = [ "preparePasswordHashes" ];

    security.sudo.enable = false;
    security.sudo-rs = {
      enable = true;
      wheelNeedsPassword = true;
      execWheelOnly = true;
    };

    programs._1password.enable = true;

    environment.systemPackages = with pkgs; [
      inputs.opnix.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];

    systemd.services.opnix-secrets = {
      requires = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # network-online.target regularly fires before DNS answers (NM reports
      # the link up, resolution lags a few seconds) and opnix burns its 3
      # attempts within ~10s, then waits RestartSec to retry. Hold the fetch
      # until the 1Password endpoint actually resolves (bounded at ~60s), and
      # shorten the retry from the module's 15min to 30s so a genuinely
      # failed boot-time fetch recovers promptly. dig, not getent: opnix's
      # resolver reads resolv.conf directly, while getent goes through
      # NSS/nscd which can lag long after direct resolution already works
      # (observed: getent still failing at +60s, opnix succeeding 3s later).
      preStart = ''
        for _ in $(${pkgs.coreutils}/bin/seq 20); do
          if ${pkgs.dnsutils}/bin/dig +short +tries=1 +time=2 my.1password.com \
            | ${pkgs.gnugrep}/bin/grep -q .; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "DNS still not resolving my.1password.com after ~60s; letting opnix try anyway" >&2
      '';
      serviceConfig.RestartSec = lib.mkForce "30s";
    };

    # sshd-keygen generates any *missing* configured host key — including the
    # opnix-provisioned one below. Unordered, it races opnix-secrets at boot
    # (both write the same path) and whoever wins determines the presented
    # host key: that was the rotating-host-key bug. Run keygen strictly after
    # opnix so it is a pure fallback for when 1Password is unreachable on a
    # host whose key was never provisioned (fresh install).
    systemd.services.sshd-keygen = {
      after = [ "opnix-secrets.service" ];
      wants = [ "opnix-secrets.service" ];
    };
    services.onepassword-secrets = {
      enable = true;
      tokenFile = "/etc/opnix-token";
      secrets = {
        sshed25519HostKey = {
          reference = "op://Shulker/${config.networking.hostName} ssh ed25519/private_key";
          mode = "0600";
          services = [ "sshd" ];
        };
      };
    };
  };
}
