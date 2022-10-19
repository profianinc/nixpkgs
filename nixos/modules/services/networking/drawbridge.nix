{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.drawbridge;

  defaultStore = "/var/lib/drawbridge";

  # TODO: Make FQDN configurable
  fqdn = config.networking.fqdn;

  certs = config.security.acme.certs.${fqdn}.directory;

  conf.toml =
    ''
      ca = "${cfg.tls.caFile}"
      cert = "${certs}/cert.pem"
      key = "${certs}/key.pem"
      oidc-client = "${cfg.oidc.client}"
      oidc-issuer = "${cfg.oidc.issuer}"
      oidc-label = "${cfg.oidc.label}"
      store = "${cfg.store.path}"
    ''
    + optionalString (cfg.oidc.secretFile != null) ''oidc-secret = "${cfg.oidc.secretFile}"'';

  configFile = pkgs.writeText "conf.toml" conf.toml;

  exposeStore = pkgs.writeShellScript "expose-${cfg.store.path}.sh" ''
    chmod 0700 ${cfg.store.path}
    chown -R drawbridge:drawbridge ${cfg.store.path}
  '';

  hideStore = pkgs.writeShellScript "hide-${cfg.store.path}.sh" ''
    chmod 0000 ${cfg.store.path}
    chown -R root:root ${cfg.store.path}
  '';
in {
  options.services.drawbridge = {
    enable = mkEnableOption "Drawbridge service.";
    package = mkOption {
      type = types.package;
      default = pkgs.drawbridge;
      defaultText = literalExpression "pkgs.drawbridge";
      description = "Drawbridge package to use.";
    };
    log.level = mkOption {
      type = with types; nullOr (enum ["trace" "debug" "info" "warn" "error"]);
      default = null;
      example = "debug";
      description = "Log level to use, if unset the default value is used.";
    };
    log.json = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to use JSON logging.";
    };
    oidc.client = mkOption {
      type = types.str;
      example = "2vq9XnQgcGZ9JCxsGERuGURYIld3mcIh";
      description = "OpenID Connect client ID to use.";
    };
    oidc.secretFile = mkOption {
      type = with types; nullOr path;
      default = null;
      example = "/var/lib/drawbridge/oidc-secret";
      description = "Path to OpenID Connect client secret file.";
    };
    oidc.issuer = mkOption {
      type = types.strMatching "(http|https)://.+";
      default = "https://auth.profian.com";
      example = "https://auth.example.com";
      description = "OpenID Connect issuer URL.";
    };
    oidc.label = mkOption {
      type = types.str;
      default = "auth.profian.com";
      example = "auth.example.com";
      description = "OpenID Connect issuer label to use in the store internally.";
    };
    store.path = mkOption {
      type = types.path;
      default = defaultStore;
      description = "Path to Drawbridge store.";
    };
    store.create = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = ''
        Wheter to create the Drawbridge store.

        When <literal>true</literal>, <literal>config.services.drawbridge.store.path</literal> will be created and used
        with 0770 permissions owned by user <literal>root</literal> and group <literal>config.services.drawbridge.group</literal>.
      '';
    };
    tls.caFile = mkOption {
      type = types.path;
      description = ''
        Path to a CA certificate, client certificates signed by which will
        grant global read-only access to all packages in the Drawbridge.

        This is normally a Steward CA certificate.
      '';
      example = literalExpression "./path/to/ca.crt";
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
        locations."/".proxyPass = "https://localhost:8080";
        recommendedTlsSettings = true;
        sslCiphers = lib.concatStringsSep ":" [
          "ECDHE-ECDSA-AES256-GCM-SHA384"
          "ECDHE-ECDSA-AES128-GCM-SHA256"
          "ECDHE-ECDSA-CHACHA20-POLY1305"
        ];
        sslProtocols = "TLSv1.3";
        sslTrustedCertificate = cfg.tls.caFile;
        extraConfig = ''
          proxy_ssl_protocols TLSv1.3;
        '';
      };

      systemd.services.drawbridge.after = [
        "network-online.target"
      ];
      systemd.services.drawbridge.description = "Drawbridge";
      systemd.services.drawbridge.environment.RUST_LOG = cfg.log.level;
      systemd.services.drawbridge.serviceConfig.DeviceAllow = "";
      systemd.services.drawbridge.serviceConfig.DynamicUser = true;
      systemd.services.drawbridge.serviceConfig.ExecPaths = ["/nix/store"];
      systemd.services.drawbridge.serviceConfig.ExecStart = "${cfg.package}/bin/drawbridge @${configFile}";
      systemd.services.drawbridge.serviceConfig.ExecStartPre = "+${exposeStore}";
      systemd.services.drawbridge.serviceConfig.ExecStop = "+${hideStore}";
      systemd.services.drawbridge.serviceConfig.InaccessiblePaths = ["-/lost+found"];
      systemd.services.drawbridge.serviceConfig.KeyringMode = "private";
      systemd.services.drawbridge.serviceConfig.LockPersonality = true;
      systemd.services.drawbridge.serviceConfig.NoExecPaths = ["/"];
      systemd.services.drawbridge.serviceConfig.NoNewPrivileges = true;
      systemd.services.drawbridge.serviceConfig.PrivateDevices = true;
      systemd.services.drawbridge.serviceConfig.PrivateMounts = "yes";
      systemd.services.drawbridge.serviceConfig.PrivateTmp = "yes";
      systemd.services.drawbridge.serviceConfig.ProtectClock = true;
      systemd.services.drawbridge.serviceConfig.ProtectControlGroups = "yes";
      systemd.services.drawbridge.serviceConfig.ProtectHome = true;
      systemd.services.drawbridge.serviceConfig.ProtectHostname = true;
      systemd.services.drawbridge.serviceConfig.ProtectKernelLogs = true;
      systemd.services.drawbridge.serviceConfig.ProtectKernelModules = true;
      systemd.services.drawbridge.serviceConfig.ProtectKernelTunables = true;
      systemd.services.drawbridge.serviceConfig.ProtectProc = "invisible";
      systemd.services.drawbridge.serviceConfig.ProtectSystem = "strict";
      systemd.services.drawbridge.serviceConfig.ReadOnlyPaths = ["/"];
      systemd.services.drawbridge.serviceConfig.ReadWritePaths = [cfg.store.path];
      systemd.services.drawbridge.serviceConfig.RemoveIPC = true;
      systemd.services.drawbridge.serviceConfig.Restart = "always";
      systemd.services.drawbridge.serviceConfig.RestrictNamespaces = true;
      systemd.services.drawbridge.serviceConfig.RestrictRealtime = true;
      systemd.services.drawbridge.serviceConfig.RestrictSUIDSGID = true;
      systemd.services.drawbridge.serviceConfig.SupplementaryGroups = [config.services.nginx.group];
      systemd.services.drawbridge.serviceConfig.SystemCallArchitectures = "native";
      systemd.services.drawbridge.serviceConfig.Type = "exec";
      systemd.services.drawbridge.serviceConfig.UMask = "0077";
      systemd.services.drawbridge.unitConfig.AssertPathExists =
        [
          cfg.tls.caFile
          configFile
        ]
        ++ optional (cfg.oidc.secretFile != null) cfg.oidc.secretFile;
      systemd.services.drawbridge.unitConfig.AssertPathIsDirectory = [cfg.store.path];
      systemd.services.drawbridge.unitConfig.AssertPathIsReadWrite = [cfg.store.path];
      systemd.services.drawbridge.wantedBy = ["multi-user.target"];
      systemd.services.drawbridge.wants = ["network-online.target"];
    }
    (mkIf cfg.store.create {
      systemd.services.drawbridge-store.before = ["drawbridge.service"];
      systemd.services.drawbridge-store.serviceConfig.DeviceAllow = "";
      systemd.services.drawbridge-store.serviceConfig.ExecPaths = ["/nix/store"];
      systemd.services.drawbridge-store.serviceConfig.ExecStart = "${pkgs.coreutils}/bin/mkdir -pv '${cfg.store.path}'";
      systemd.services.drawbridge-store.serviceConfig.InaccessiblePaths = ["-/lost+found"];
      systemd.services.drawbridge-store.serviceConfig.KeyringMode = "private";
      systemd.services.drawbridge-store.serviceConfig.LockPersonality = true;
      systemd.services.drawbridge-store.serviceConfig.NoExecPaths = ["/"];
      systemd.services.drawbridge-store.serviceConfig.NoNewPrivileges = true;
      systemd.services.drawbridge-store.serviceConfig.PrivateDevices = true;
      systemd.services.drawbridge-store.serviceConfig.PrivateTmp = "yes";
      systemd.services.drawbridge-store.serviceConfig.ProtectClock = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectControlGroups = "yes";
      systemd.services.drawbridge-store.serviceConfig.ProtectHome = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectHostname = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectKernelLogs = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectKernelModules = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectKernelTunables = true;
      systemd.services.drawbridge-store.serviceConfig.ProtectProc = "invisible";
      systemd.services.drawbridge-store.serviceConfig.RemoveIPC = true;
      systemd.services.drawbridge-store.serviceConfig.RestrictRealtime = true;
      systemd.services.drawbridge-store.serviceConfig.RestrictSUIDSGID = true;
      systemd.services.drawbridge-store.serviceConfig.SystemCallArchitectures = "native";
      systemd.services.drawbridge-store.serviceConfig.Type = "oneshot";
      systemd.services.drawbridge-store.serviceConfig.UMask = "0777";
      systemd.services.drawbridge-store.wantedBy = ["drawbridge.service"];
    })
    (mkIf (cfg.log.json) {
      systemd.services.drawbridge.environment.RUST_LOG_JSON = "true";
    })
  ]);
}
