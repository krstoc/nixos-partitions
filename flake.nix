{
  description = "Declarative partition mounting for NixOS";

  outputs = { self }: {
    nixosModules.default = ./partitions.nix;
  };
}
