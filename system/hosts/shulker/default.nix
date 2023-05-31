{ ... }:

{
  imports = [ 
    ./hardware.nix 
    #./minecraft.nix
  ];

  networking.firewall = {
    allowedTCPPorts = [ 80 443 8888 23231 ];
  };

  ## AgentGPT redirection
  services.nginx = {
    enable = true;
    virtualHosts."AgentGPT" = {
      serverName = "gpt.shulker.fr";
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:23233";
      };
    };
  };

  shulker = {
    modules = {
      user.home = ./home.nix;
      ssh_server.enable = true;
      yubikey.enable = true;
      soft-serve.enable = true;
      docker.enable = true;
      searx = {
        enable = true;
        port = 23232;
        url = "searx.shulker.fr";
        secret_key = "SUPER_USEFUL_SECRET_KEY_I_NEED_TO_SETUP_A_GOOD_SECRET_MANAGEMENT_NOW-sdhftjdxhshrserhds34568TSDGXHFZ44YERGEZ3ETSYRRDGfegzetsgezt";
      };
      wireguard.server = {
      	enable = true;
      	extInterface = "ens3";
      };
    };
  };
}
