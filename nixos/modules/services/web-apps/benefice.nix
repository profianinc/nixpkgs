{
  config,
  lib,
  options,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.benefice;

  # TODO: Make FQDN configurable
  fqdn = config.networking.fqdn;

  ss = "${pkgs.iproute}/bin/ss";
  conf.toml =
    ''
      runtime-dir = "/run/benefice"
      ss-command = "${ss}"
      oci-command = "${cfg.oci.command}"
      oidc-client = "${cfg.oidc.client}"
      oidc-issuer = "${cfg.oidc.issuer}"
      url = "https://${fqdn}"
    ''
    + optionalString (cfg.oidc.secretFile != null) ''oidc-secret = "${cfg.oidc.secretFile}"'';

  configFile = pkgs.writeText "conf.toml" conf.toml;
in {
  options.services.benefice = {
    enable = mkEnableOption "Benefice service.";
    package = mkOption {
      type = types.package;
      default = pkgs.benefice;
      defaultText = literalExpression "pkgs.benefice";
      description = "Benefice package to use.";
    };
    log.level = mkOption {
      type = with types; nullOr (enum ["trace" "debug" "info" "warn" "error"]);
      default = null;
      example = "debug";
      description = "Log level to use, if unset the default value is used.";
    };
    oidc.client = mkOption {
      type = types.str;
      example = "23Lt09AjF8HpUeCCwlfhuV34e2dKD1MH";
      description = "OpenID Connect client ID to use.";
    };
    oidc.secretFile = mkOption {
      type = with types; nullOr path;
      default = null;
      example = "/var/lib/benefice/oidc-secret";
      description = "Path to OpenID Connect client secret file.";
    };
    oidc.issuer = mkOption {
      type = types.strMatching "(http|https)://.+";
      default = "https://auth.profian.com";
      example = "https://auth.example.com";
      description = "OpenID Connect issuer URL.";
    };
    enarx.backend = options.services.enarx.backend;
    oci.backend = mkOption {
      type = with types; nullOr (enum ["docker" "podman"]);
      default = "docker";
      example = null;
      description = "OCI container engine to use. If <literal>null</literal>, <option>services.benefice.oci.command</option> must be set.";
    };
    oci.command = mkOption {
      type = types.path;
      description = "OCI container engine command to use. This option must be set if and only if <option>services.benefice.oci.backend</option> is <literal>null</literal>.";
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
        locations."/".proxyPass = "http://localhost:3000";
      };

      systemd.services.benefice.after = [
        "network-online.target"
        "systemd-udevd.service"
      ];
      systemd.services.benefice.description = "Benefice";
      systemd.services.benefice.environment.RUST_LOG = cfg.log.level;
      systemd.services.benefice.serviceConfig.DynamicUser = true;
      systemd.services.benefice.serviceConfig.ExecPaths = ["/nix/store"];
      systemd.services.benefice.serviceConfig.ExecStart = "${cfg.package}/bin/benefice @${configFile}";
      systemd.services.benefice.serviceConfig.InaccessiblePaths = "-/lost+found";
      systemd.services.benefice.serviceConfig.KeyringMode = "private";
      systemd.services.benefice.serviceConfig.LockPersonality = true;
      systemd.services.benefice.serviceConfig.NoExecPaths = ["/"];
      systemd.services.benefice.serviceConfig.NoNewPrivileges = true;
      systemd.services.benefice.serviceConfig.PrivateMounts = "yes";
      systemd.services.benefice.serviceConfig.PrivateTmp = "yes";
      systemd.services.benefice.serviceConfig.ProtectClock = true;
      systemd.services.benefice.serviceConfig.ProtectControlGroups = "yes";
      systemd.services.benefice.serviceConfig.ProtectHome = true;
      systemd.services.benefice.serviceConfig.ProtectHostname = true;
      systemd.services.benefice.serviceConfig.ProtectKernelLogs = true;
      systemd.services.benefice.serviceConfig.ProtectKernelModules = true;
      systemd.services.benefice.serviceConfig.ProtectKernelTunables = true;
      systemd.services.benefice.serviceConfig.ProtectProc = "invisible";
      systemd.services.benefice.serviceConfig.ProtectSystem = "strict";
      systemd.services.benefice.serviceConfig.ReadOnlyPaths = ["/"];
      systemd.services.benefice.serviceConfig.ReadWritePaths = [
        "/tmp"
        "/var/tmp"
      ];
      systemd.services.benefice.serviceConfig.RemoveIPC = true;
      systemd.services.benefice.serviceConfig.Restart = "always";
      systemd.services.benefice.serviceConfig.RestrictNamespaces = true;
      systemd.services.benefice.serviceConfig.RestrictRealtime = true;
      systemd.services.benefice.serviceConfig.RestrictSUIDSGID = true;
      systemd.services.benefice.serviceConfig.RuntimeDirectory = "benefice";
      systemd.services.benefice.serviceConfig.SystemCallArchitectures = "native";
      systemd.services.benefice.serviceConfig.Type = "exec";
      systemd.services.benefice.serviceConfig.UMask = "0077";
      systemd.services.benefice.unitConfig.AssertFileIsExecutable = [cfg.oci.command];
      systemd.services.benefice.unitConfig.AssertPathExists =
        [
          configFile
        ]
        ++ optional (cfg.oidc.secretFile != null) cfg.oidc.secretFile;
      systemd.services.benefice.wantedBy = ["multi-user.target"];
      systemd.services.benefice.wants = ["network-online.target"];

      systemd.services.benefice.environment.ENARX_BACKEND = cfg.enarx.backend;
    }
    (mkIf (cfg.oci.backend == "docker") {
      assertions = [
        {
          assertion = config.virtualisation.docker.enable;
          message = "Docker support is not enabled";
        }
      ];
      services.benefice.oci.command = "${config.virtualisation.docker.package}/bin/docker";
    })
    (mkIf (cfg.oci.backend == "podman") {
      assertions = [
        {
          assertion = config.virtualisation.podman.enable;
          message = "Podman support is not enabled";
        }
      ];
      services.benefice.oci.command = "${pkgs.podman}/bin/podman";
    })
    (mkIf (cfg.enarx.backend == null) {
      systemd.services.benefice.serviceConfig.DeviceAllow = [
        "/dev/kvm rw"
        "/dev/sev rw"
        "/dev/sgx_enclave rw"
        "/dev/sgx_provision rw"
      ];
    })
    (mkIf (cfg.enarx.backend == "sgx") {
      systemd.services.benefice.serviceConfig.DeviceAllow = ["/dev/sgx_enclave rw"];
      systemd.services.benefice.serviceConfig.SupplementaryGroups = ["sgx"];
      systemd.services.benefice.unitConfig.AssertPathIsReadWrite = ["/dev/sgx_enclave"];
    })
    (mkIf (cfg.enarx.backend == "sev") {
      systemd.services.benefice.serviceConfig.DeviceAllow = [
        "/dev/kvm rw"
        "/dev/sev rw"
      ];
      systemd.services.benefice.serviceConfig.LimitMEMLOCK = "8G";
      systemd.services.benefice.serviceConfig.SupplementaryGroups = [config.hardware.cpu.amd.sev.group];
      systemd.services.benefice.unitConfig.AssertPathIsReadWrite = [
        "/dev/kvm"
        "/dev/sev"
      ];
    })
  ]);
}
