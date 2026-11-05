{inputs, ...}: {
  imports = [
    inputs.flake-file.flakeModules.dendritic
    # Exports neoPlugin.modules for Neo (once per plugin instance, each with
    # its own prefix) and nixosModules.default.
    inputs.neo.flakeModules.plugin
  ];
  flake-file.outputs = "inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./nix)";
}
