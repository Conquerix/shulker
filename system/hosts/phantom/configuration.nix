{ pkgs, ... }: {
  imports = [
    ./home.nix
  ];

  boot.cleanTmpDir = true;
  zramSwap.enable = true;
  networking.hostName = "phantom";

  time.timeZone= "Europe/Paris";

  users.mutableUsers = false;

  users.users.conquerix = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialHashedPassword = "$6$Na7d9SJRCkC6FyK7$3K.rYNPXX1.aeJe8f.2ylE2ITGLgxqv3CFvVYRsTiarQjFNZ.p2QZ/MIu1n6qz6wOO44lXU6wc9kmgIV.wboC/";
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV" ];
  };

  environment.systemPackages = with pkgs; [
    micro
    wget
    neofetch
    htop
    git
    python37
    ocaml
    bat
    emacs
    agda
    emacs28Packages.agda2-mode
  ];

  services.emacs.package = with pkgs; ((emacsPackagesFor emacsPgtkGcc).emacsWithPackages (epkgs: [ epkgs.vterm epkgs.tuareg]));
  
  services.tor = {
  	enable = true;
  	client.enable = true;
  	torsocks.enable = true;
  };

  system.stateVersion = "22.05";
}
