{
  description = "Declarative partition mounting for NixOS";

  outputs = { self }: {
    nixosModules.default = ./modules/partitions.nix;
  };
}
