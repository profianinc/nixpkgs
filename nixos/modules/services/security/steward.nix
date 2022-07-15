{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.steward;

  defaultStore = "/var/lib/steward";

  # TODO: Make FQDN configurable
  fqdn = config.networking.fqdn;

  conf.toml = ''
    crt = "${cfg.certFile}"
    key = "${cfg.keyFile}"
  '';

  configFile = pkgs.writeText "conf.toml" conf.toml;
in {
  options.services.steward = {
    enable = mkEnableOption "Steward service.";
    package = mkOption {
      type = types.package;
      default = pkgs.steward;
      defaultText = literalExpression "pkgs.steward";
      description = "Steward package to use.";
    };
    log.level = mkOption {
      type = with types; nullOr (enum ["trace" "debug" "info" "warn" "error"]);
      default = null;
      example = "debug";
      description = "Log level to use, if unset the default value is used.";
    };
    certFile = mkOption {
      type = types.path;
      description = ''
        Path to a certificate used by the Steward to issue certificates to
        remote parties on successful attestation.
      '';
      example = literalExpression "./path/to/ca.crt";
    };
    keyFile = mkOption {
      type = types.path;
      description = ''
        Path to a private key of certificate used by the Steward to issue certificates to
        remote parties on successful attestation.
      '';
      example = literalExpression "./path/to/ca.key";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = config.services.nginx.enable;
          message = "Nginx service is not enabled";
        }
      ];

      environment.systemPackages = [
        cfg.package
      ];

      services.nginx.virtualHosts.${fqdn} = {
        enableACME = true;
        forceSSL = true;
        http2 = false;
        locations."/".proxyPass = "http://localhost:3000";
      };

      systemd.services.steward.after = [
        "network-online.target"
      ];
      systemd.services.steward.description = "Steward";
      systemd.services.steward.environment.RUST_LOG = cfg.log.level;
      systemd.services.steward.serviceConfig.DeviceAllow = [""];
      systemd.services.steward.serviceConfig.DynamicUser = true;
      systemd.services.steward.serviceConfig.ExecPaths = ["/nix/store"];
      systemd.services.steward.serviceConfig.ExecStart = "${cfg.package}/bin/steward @${configFile}";
      systemd.services.steward.serviceConfig.InaccessiblePaths = ["-/lost+found"];
      systemd.services.steward.serviceConfig.KeyringMode = "private";
      systemd.services.steward.serviceConfig.LockPersonality = true;
      systemd.services.steward.serviceConfig.NoExecPaths = ["/"];
      systemd.services.steward.serviceConfig.NoNewPrivileges = true;
      systemd.services.steward.serviceConfig.PrivateDevices = true;
      systemd.services.steward.serviceConfig.PrivateMounts = "yes";
      systemd.services.steward.serviceConfig.PrivateTmp = "yes";
      systemd.services.steward.serviceConfig.ProtectClock = true;
      systemd.services.steward.serviceConfig.ProtectControlGroups = "yes";
      systemd.services.steward.serviceConfig.ProtectHome = true;
      systemd.services.steward.serviceConfig.ProtectHostname = true;
      systemd.services.steward.serviceConfig.ProtectKernelLogs = true;
      systemd.services.steward.serviceConfig.ProtectKernelModules = true;
      systemd.services.steward.serviceConfig.ProtectKernelTunables = true;
      systemd.services.steward.serviceConfig.ProtectProc = "invisible";
      systemd.services.steward.serviceConfig.ProtectSystem = "strict";
      systemd.services.steward.serviceConfig.ReadOnlyPaths = ["/"];
      systemd.services.steward.serviceConfig.RemoveIPC = true;
      systemd.services.steward.serviceConfig.Restart = "always";
      systemd.services.steward.serviceConfig.RestrictNamespaces = true;
      systemd.services.steward.serviceConfig.RestrictRealtime = true;
      systemd.services.steward.serviceConfig.RestrictSUIDSGID = true;
      systemd.services.steward.serviceConfig.SystemCallArchitectures = "native";
      systemd.services.steward.serviceConfig.Type = "exec";
      systemd.services.steward.serviceConfig.UMask = "0077";
      systemd.services.steward.unitConfig.AssertPathExists = [
        cfg.certFile
        cfg.keyFile
        configFile
      ];
      systemd.services.steward.wantedBy = ["multi-user.target"];
      systemd.services.steward.wants = ["network-online.target"];
    }
  ]);
}
