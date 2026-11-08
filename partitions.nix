{ config, lib, pkgs, ... }:

let
  cfg = config.partitions;

  partitionType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Partition name and default mount directory name.";
      };

      device = lib.mkOption {
        type = lib.types.str;
        description = ''
          Kernel device name, such as sda1 or nvme0n1p2.
          A full /dev/... path is also accepted.
        '';
      };

      owner = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional owner username.";
      };

      group = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional group name.";
      };

      permissions = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Optional three-digit octal permissions for the mounted
          filesystem root, for example 755 or 700.
        '';
      };

      path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Optional absolute mountpoint path.

          If unset and an owner is specified, use the owner's home
          directory followed by Partitions/<name>.

          If unset and no owner is specified, use /mnt/<name>.
        '';
      };
    };
  };

  partitionNames = map (p: p.name) cfg;

  mountPaths = map
    (p:
      if p.path != null then
        p.path
      else if p.owner != null then
        "/home/${p.owner}/Partitions/${p.name}"
      else
        "/mnt/${p.name}"
    )
    cfg;

  # Package the scripts separately from this Nix module. Their configuration
  # is supplied through the systemd service environment below.
  mountPartitionScript = pkgs.writeShellApplication {
    name = "mount-partition";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      getent
      ntfs3g
    ];
    text = builtins.readFile ./scripts/mount-partition.sh;
  };

  unmountPartitionScript = pkgs.writeShellApplication {
    name = "unmount-partition";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    text = builtins.readFile ./scripts/unmount-partition.sh;
  };

  services = builtins.listToAttrs (
    map
      (p: {
        name = "partition-${p.name}";

        value = {
          description = "Mount partition ${p.name}";

          wantedBy = [ "multi-user.target" ];
          after = [ "local-fs.target" ];
          before = [ "multi-user.target" ];

          # Pass per-partition configuration to the standalone scripts.
          environment = {
            PARTITION_NAME = p.name;
            PARTITION_DEVICE = p.device;
            PARTITION_OWNER = if p.owner == null then "" else p.owner;
            PARTITION_GROUP = if p.group == null then "" else p.group;
            PARTITION_PERMISSIONS = if p.permissions == null then "" else p.permissions;
            PARTITION_PATH = if p.path == null then "" else p.path;
          };

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "45s";
            TimeoutStopSec = "30s";
            ExecStart = "${mountPartitionScript}/bin/mount-partition";
            ExecStop = "${unmountPartitionScript}/bin/unmount-partition";
          };
        };
      })
      cfg
  );
in
{
  options.partitions = lib.mkOption {
    type = lib.types.listOf partitionType;
    default = [ ];
    description = "Declarative partition mount definitions.";
  };

  config = {
    assertions = [
      {
        assertion =
          builtins.length partitionNames
          == builtins.length (lib.unique partitionNames);
        message = "partitions must not contain duplicate names.";
      }

      {
        assertion = lib.all
          (p:
            builtins.match "[^A-Za-z0-9_-][A-Za-z0-9._-]*" p.name != null
          )
          cfg;
        message = ''
          Partition names must begin with a letter, number, underscore,
          or hyphen and contain only letters, numbers, underscores,
          hyphens, or dots.
        '';
      }

      {
        assertion =
          builtins.length mountPaths
          == builtins.length (lib.unique mountPaths);
        message = "partitions must not contain duplicate mount paths.";
      }

      {
        assertion = lib.all
          (p: p.path == null || lib.hasPrefix "/" p.path)
          cfg;
        message = "Explicit partition paths must be absolute paths.";
      }

      {
        assertion = lib.all
          (p:
            p.permissions == null
            || builtins.match "[0-7][0-7][0-7]" p.permissions != null
          )
          cfg;
        message = ''
          Partition permissions must be null or three-digit octal strings,
          such as "755", "700", or "640".
        '';
      }
    ];

    systemd.services = services;
  };
}
