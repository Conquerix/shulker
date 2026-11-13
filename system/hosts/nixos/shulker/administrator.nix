{ ... }:
{
  # Preserve the exact live Administrator runtime and its independent identity.
  shulker.system.modules.hermes-agent.instances.administrator = {
    containerName = "hermes-administrator";
    stateDir = "/var/lib/hermes-administrator";
    image = "docker.io/nousresearch/hermes-agent:stable@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
    omh.enable = true;
    dashboard.enable = false;
    discord = {
      enable = true;
      allowedUsers = [ "240780407442767873" ];
    };
    credentials = {
      discord = {
        reference = "op://Shulker/cjhj7apkfpih3563gmmwfkxwpa/lmpd3oitveqsn5sc45ivndy7vq/kx2e3k4gf5us5uzkldv6vxuxzu";
        requiredKeys = [ "DISCORD_BOT_TOKEN" ];
      };
      provider = {
        reference = "op://Shulker/shulker/Hermes/Provider environment";
        requiredKeys = [ "HERMES_OMNIROUTE_API_KEY" ];
      };
    };
    serviceAccount = {
      enable = true;
      reference = "op://Shulker/xnfhxswtgjisgzwdzwwmdn4mdq/serviceAccountToken";
    };
    hostAdministration = {
      enable = true;
      user = "hermes-administrator-operator";
      privateKeyReference = "op://Shulker/xnfhxswtgjisgzwdzwwmdn4mdq/sshPrivateKey";
      sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA19qW3CZaTPb8npm8SfQLtK558Jm9nwwZ3b8FqHYIDY administrator@shulker";
      hostPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHsMHVJJq7B5xr8y49tstCoN9DotgIPg1eSOMCBQ4MaT";
    };
    initial = {
      settings = {
        "model.default" = "cx/gpt-6.1-sol";
        "model.provider" = "omniroute";
        "model.base_url" = "http://omniroute:20128/v1";
        "model.api_key" = "\${HERMES_OMNIROUTE_API_KEY}";
      };
      plugins = [ "discord-platform" ];
    };
  };
}
