{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.rathole;
in {
  options = {
    services.rathole = {
      enable = mkEnableOption "Rathole service";

      configurations = mkOption {
        type = with types;
          attrsOf (submodule {
            options.path = mkOption {
              type = types.path;
              description = ''
                Path to Rathole configuration file.
              '';
            };

            options.mode = mkOption {
              type = with types; nullOr (enum ["client" "server"]);
              default = null;
              example = "client";
              description = "Mode to operate in, if unset it is determined at runtime from the config.";
            };
          });
        default = {};
        description = ''
          Rathole configurations to activate on the system as systemd services.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = with pkgs; [rathole];

    systemd.services = mapAttrs' (name: cfg:
      nameValuePair "rathole-${name}" {
        # Adapted from https://github.com/rapiz1/rathole/tree/ef154cb56ba87509c1879b72fcfd6708e1563d67/examples/systemd
        after = ["network.target"];
        description = "Rathole ${name} service";
        serviceConfig.DynamicUser = true;
        serviceConfig.ExecPaths = ["/nix/store"];
        serviceConfig.ExecStart = "${pkgs.rathole}/bin/rathole ${optionalString (cfg.mode != null) "--${cfg.mode}"} ${cfg.path}";
        serviceConfig.InaccessiblePaths = ["-/lost+found"];
        serviceConfig.KeyringMode = "private";
        serviceConfig.LimitNOFILE = 1048576;
        serviceConfig.LockPersonality = true;
        serviceConfig.NoExecPaths = ["/"];
        serviceConfig.NoNewPrivileges = true;
        serviceConfig.PrivateTmp = "yes";
        serviceConfig.ProtectClock = true;
        serviceConfig.ProtectControlGroups = "yes";
        serviceConfig.ProtectHome = true;
        serviceConfig.ProtectHostname = true;
        serviceConfig.ProtectKernelLogs = true;
        serviceConfig.ProtectKernelModules = true;
        serviceConfig.ProtectKernelTunables = true;
        serviceConfig.ProtectProc = "invisible";
        serviceConfig.ReadOnlyPaths = ["/"];
        serviceConfig.RemoveIPC = true;
        serviceConfig.Restart = "on-failure";
        serviceConfig.RestartSec = "5s";
        serviceConfig.RestrictRealtime = true;
        serviceConfig.RestrictSUIDSGID = true;
        serviceConfig.SystemCallArchitectures = "native";
        serviceConfig.Type = "exec";
        serviceConfig.UMask = "0777";
        unitConfig.AssertPathExists = [cfg.path];
        wantedBy = ["multi-user.target"];
      })
    cfg.configurations;
  };
}
