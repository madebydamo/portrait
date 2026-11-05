# The NixOS side lives in neoPlugin.modules.* (nix/services); inputs.neo.flakeModules.plugin
# (nix/imports.nix) exports it. Every name goes through plugin.name, so Neo can add
# this plugin twice under different prefixes (for example a dev branch next to main).
{...}: {
  systems = ["x86_64-linux"];
  perSystem = {pkgs, ...}: {
    formatter = pkgs.alejandra;
  };
}
