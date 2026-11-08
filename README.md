# Declarative partition mounts

A small NixOS module that declaratively mounts additional partitions at boot
using one `systemd` oneshot service per partition.

## Installation

Keep the module files together:

```text
nixos-partitions/
├── partitions.nix
├── README.md
├── LICENSE
└── scripts/
    ├── mount-partition.sh
    └── unmount-partition.sh
```

Import `partitions.nix` from your NixOS configuration:

```nix
{
  imports = [
    ./modules/nixos-partitions/partitions.nix
  ];
}
```

## How to use it

Define the partitions using the top-level `partitions` option:

```nix
{
  # List of partitions which will be mounted at boot.
  partitions = [
    {
      # Partition name. Also used in the generated systemd service name.
      name = "windows-drive";
      device = "sda1";

      # Because an owner is specified, the default mountpoint is:
      # /home/bob/Partitions/windows-drive
      owner = "bob";
      group = "users";

      # On ext4 and other native Linux filesystems, this applies only to
      # the mounted filesystem's root directory; it is not recursive.
      # On NTFS and FAT-family filesystems, ownership and permissions are
      # represented through mount options and can affect all directories.
      permissions = "755";
    }

    {
      name = "storage";
      device = "sdb1";

      # With no owner or explicit path, the mountpoint is /mnt/storage.
    }

    {
      name = "backup";
      device = "sdb2";
      owner = "alice";

      # An explicit path overrides the default mountpoint:
      # /mnt/backup
      path = "/mnt/backup";
    }
  ];
}
```

## Options

Each entry in `partitions` supports these options:

| Option | Required | Description |
|---|---|---|
| `name` | Yes | Partition name. Used to form the default mountpoint and systemd service name. |
| `device` | Yes | Kernel device name, such as `sda1` or `nvme0n1p2`. A full `/dev/...` path is also accepted. |
| `owner` | No | Username to own the mounted filesystem root, or to set as the synthetic owner on supported filesystems. Defaults to `null`. |
| `group` | No | Group to apply to the mounted filesystem root, or to set as the synthetic group on supported filesystems. Defaults to `null`. |
| `permissions` | No | Three-digit octal permissions, such as `755`, `700`, or `640`. Defaults to `null`. |
| `path` | No | Explicit absolute mountpoint. Defaults to `null`, which enables automatic mountpoint selection. |

### Default mountpoints

If `path` is not specified, the mountpoint is selected as follows:

- If `owner` is specified: the owner's home directory followed by
  `Partitions/<name>` (for example, `/home/bob/Partitions/windows-drive`).
  The script resolves the user's actual home directory at runtime.
- If `owner` is not specified: `/mnt/<name>` (for example, `/mnt/storage`).

An explicit `path` always takes precedence over these defaults.

### Ownership and permissions

For native Linux filesystems, such as ext4, ownership and permissions are
stored as filesystem metadata. The module applies requested ownership and
permissions to the mounted filesystem's root directory only; it does not
recursively modify existing files and directories.

For FAT-family and NTFS-style filesystems, ownership and permissions are
usually represented by mount options instead. The configured owner, group,
and permissions can therefore affect the ownership and permissions reported
for directories and files throughout the mounted filesystem.

## How it works

- A `partition-<name>` systemd oneshot service is generated for each entry.
- The services are started as part of `multi-user.target`.
- The mount script waits briefly for the device to appear, detects its
  filesystem type and UUID, and mounts it.
- NTFS filesystems are attempted with `ntfs3` first and `ntfs-3g` as a fallback.
- The service remembers the actual mountpoint so its stop script can unmount
  it cleanly when the service stops, including during shutdown.
- The shell scripts are packaged with `pkgs.writeShellApplication`, which
  provides their runtime dependencies.

## Validation

The module checks that:

- partition names are unique and contain only permitted characters;
- mountpoints are unique;
- explicitly configured mountpoints are absolute paths; and
- `permissions`, when specified, is a three-digit octal string.
