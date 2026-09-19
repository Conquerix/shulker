{ lib, ... }:
{
  # Discover language-specific development modules from child directories.
  imports = lib.custom.scanPaths ./.;
}
