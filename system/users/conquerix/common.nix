{
  pkgs,
  ...
}:

# let
#   cfg = config.shulker.users.conquerix;
# in
{
  config = {
    users.users.conquerix = {
      uid = 1000;
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcuA0ZxQyqfHlWrbdVT9Hu7/IQwZuh4aQa6X1gIHOSV"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILCQToe+S6lXjwMCrcg9smHlb8tEp2613jW/lOkfSSm1"
      ];
    };
  };
}
