# Declarative partition mounts

A small NixOS module that declaratively mounts additional partitions at boot
using one `systemd` oneshot service per partition.

## Motivation

I didn't want to have to mount my partitions manually every time I log into my computer because I had to write my sudo password everytime.
And I wanted to mount some of my drives immediately when computer is booting, while udisks2 service would mount them on demand.

## Getting started

Add `nixos-partitions` to your NixOS configuration managed with flakes.

### 1. Add the module to your flake

Open your system's `flake.nix` and add `nixos-partitions` to the `inputs` attribute.
Make sure your `inputs` are passed to your NixOS modules through `specialArgs`.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-partitions.url = "github:krstoc/nixos-partitions";
  };

  outputs = inputs@{ nixpkgs, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";

      # Pass flake inputs to your NixOS modules.
      specialArgs = {
        inherit inputs;
      };

      modules = [
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Import the module

Open your main NixOS configuration file (for example, `host.nix` or `configuration.nix`).

Add the module to your imports:

```nix
{ inputs, ... }:

{
  imports = [
    inputs.nixos-partitions.nixosModules.default
  ];
}
```

The module is now available in your NixOS configuration.

### 3. Configure your partitions

Add the `partitions` option to your configuration.

For example:

```nix
{
  partitions = [
    {
      # Windows partition.
      name = "windows-drive";
      device = "sda1";

      owner = "alice";
      group = "users";
      permissions = "755";
    }

    # Additional storage partition.
    {
      name = "storage";
      device = "sdb1";
    }

    # Backup partition with a custom mountpoint.
    {
      name = "backup";
      device = "sdb2";
      owner = "alice";
      path = "/mnt/backup";
    }
  ];
}
```

Each entry represents one partition that will be mounted automatically during system startup.

### 4. Rebuild your system

Run

```bash
sudo nixos-rebuild switch --flake .#my-host
```

Nix will fetch the module, evaluate your configuration, and create the necessary systemd services.

### 5. Verify the mounts

After rebuilding, check whether your partitions were mounted:

```bash
lsblk -f
```

You can also inspect a generated systemd service:

```bash
systemctl status partition-windows-drive.service
```

To see all configured partition services:

```bash
systemctl list-units 'partition-*'
```

Your partitions should now be available at their respective mountpoints.

---

## Configuration reference

Every partition entry supports the following options:

| Option | Required | Description |
|---|---|---|
| `name` | Yes | Partition name. Also used to generate the systemd service name. |
| `device` | Yes | Device name, such as `sda1` or `nvme0n1p2`. Full `/dev/...` paths are also accepted. |
| `owner` | No | Username that should own the mounted filesystem. |
| `group` | No | Group that should own the mounted filesystem. |
| `permissions` | No | Three-digit octal permissions, such as `"755"` or `"700"`. |
| `path` | No | Explicit absolute mountpoint. |

### Default mountpoints

If `path` is not specified, the module automatically selects a mountpoint:

- **With an owner:** `/home/<owner>/Partitions/<name>`
- **Without an owner:** `/mnt/<name>`

An explicitly configured `path` always takes precedence.

The owner's actual home directory is resolved at runtime.

### Ownership and permissions

The module handles ownership and permissions differently depending on the filesystem.

**Linux filesystems (ext4, btrfs, etc.)**

Ownership and permissions are applied to the root directory of the mounted filesystem. Existing files and directories are not modified recursively.
This is the general case for most filesystems.

**NTFS and FAT-family filesystems**

On these filesystems the permissions and ownership of the mountpoint will apply to the entire mounted partition.

---

## How it works

For every configured partition, the module generates a dedicated systemd oneshot service.

During startup, the service:

1. Waits briefly for the partition device to become available.
2. Detects the filesystem type and UUID.
3. Determines the appropriate mountpoint.
4. Mounts the partition.
5. Applies the requested ownership and permissions.

NTFS partitions are mounted using `ntfs3`, with `ntfs-3g` as a fallback.

The module also generates an unmount script for each partition, allowing the service to cleanly unmount it when stopped, including during system shutdown.

## Validation

The module validates the configuration to ensure that:

- Partition names are unique and contain only permitted characters.
- Mountpoints are unique.
- Explicit mountpoints are absolute paths.
- Permissions, when specified, use three-digit octal notation.
