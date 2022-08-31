{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.benefice;

  # TODO: Make FQDN configurable
  fqdn = config.networking.fqdn;

  devices = with cfg.enarx;
    if backend == "kvm"
    then [
      "/dev/kvm"
    ]
    else if backend == "sgx"
    then [
      "/dev/sgx_enclave"
    ]
    else if backend == "sev"
    then [
      "/dev/kvm"
      "/dev/sev"
    ]
    else [];

  ss = "${pkgs.iproute}/bin/ss";
  conf.toml =
    ''
      ss-command = "${ss}"
      oci-command = "${cfg.oci.command}"
      oidc-client = "${cfg.oidc.client}"
      oidc-issuer = "${cfg.oidc.issuer}"
      url = "https://${fqdn}"
    ''
    + optionalString (length devices > 0) ''
      devices = [ ${concatMapStringsSep "," (dev: ''"${dev}"'') devices} ]
    ''
    + optionalString (cfg.enarx.backend == "sev") ''
      privileged = true
      paths = [ "/var/cache/amd-sev" ]
    ''
    + optionalString (cfg.enarx.backend == "sgx") ''
      paths = [ "/var/run/aesmd/aesm.socket" ]
    ''
    + optionalString (cfg.oci.image != null) ''
      oci-image = "${cfg.oci.image}"
    ''
    + optionalString (cfg.oidc.secretFile != null) ''
      oidc-secret = "${cfg.oidc.secretFile}"
    '';

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
    enarx.backend = mkOption {
      type = types.enum ["nil" "kvm" "sgx" "sev"];
      description = "Enarx backend to use.";
    };
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
    oci.image = mkOption {
      type = with types; nullOr str;
      default = null;
      example = "enarx/enarx:0.6.3";
      description = "OCI container image to use.";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      environment.systemPackages = [
        cfg.package
      ];

      services.nginx.enable = true;
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
      systemd.services.benefice.environment.ENARX_BACKEND = cfg.enarx.backend;
      systemd.services.benefice.environment.RUST_LOG = cfg.log.level;
      systemd.services.benefice.path = with pkgs; [
        iproute
      ];
      systemd.services.benefice.serviceConfig.DeviceAllow = map (dev: "${dev} rw") devices;
      systemd.services.benefice.serviceConfig.ExecStart = "${cfg.package}/bin/benefice @${configFile}";
      systemd.services.benefice.serviceConfig.Restart = "always";
      systemd.services.benefice.serviceConfig.Type = "exec";
      systemd.services.benefice.serviceConfig.UMask = "0077";
      systemd.services.benefice.unitConfig.AssertFileIsExecutable = [
        cfg.oci.command
        ss
      ];
      systemd.services.benefice.unitConfig.AssertPathExists =
        [
          configFile
        ]
        ++ optional (cfg.oidc.secretFile != null) cfg.oidc.secretFile;
      systemd.services.benefice.unitConfig.AssertPathIsReadWrite = devices;
      systemd.services.benefice.wantedBy = ["multi-user.target"];
      systemd.services.benefice.wants = ["network-online.target"];
    }
    (mkIf (cfg.oci.backend == "docker") {
      services.benefice.oci.command = "${config.virtualisation.docker.package}/bin/docker";

      systemd.services.benefice.path = [
        config.virtualisation.docker.package
      ];

      virtualisation.docker.enable = true;
    })
    (mkIf (cfg.oci.backend == "podman") {
      services.benefice.oci.command = "${pkgs.podman}/bin/podman";

      systemd.services.benefice.path = [
        "/run/wrappers"
        pkgs.podman
      ];
      systemd.services.benefice.after = ["benefice-linger.service"];
      systemd.services.benefice.serviceConfig.Group = config.users.groups.benefice.name;
      systemd.services.benefice.serviceConfig.ReadWritePaths = [
        config.users.users.benefice.home
      ];
      systemd.services.benefice.serviceConfig.User = config.users.users.benefice.name;

      systemd.services.benefice-linger.serviceConfig.ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger ${config.users.users.benefice.name}";
      systemd.services.benefice-linger.serviceConfig.Type = "oneshot";
      systemd.services.benefice-linger.wantedBy = ["multi-user.target"];

      users.groups.benefice = {};
      users.users.benefice.group = config.users.groups.benefice.name;
      # this is required to create and set HOME for `podman`
      users.users.benefice.isNormalUser = true;

      virtualisation.podman.enable = true;
    })
    (mkIf (cfg.enarx.backend == "kvm") {
      systemd.services.benefice.serviceConfig.SupplementaryGroups = [config.users.groups.kvm.name];
    })
    (mkIf (cfg.enarx.backend == "sgx") {
      assertions = [
        {
          assertion = cfg.oci.backend == "docker";
          message = "Docker is the only OCI backend currently supported on SGX";
        }
      ];

      systemd.services.benefice.serviceConfig.ReadWritePaths = [
        "/var/run/aesmd/aesm.socket"
      ];
      systemd.services.benefice.serviceConfig.SupplementaryGroups = [config.users.groups.sgx.name];
    })
    (mkIf (cfg.enarx.backend == "sev") {
      assertions = [
        {
          assertion = cfg.oci.backend == "docker";
          message = "Docker is the only OCI backend currently supported on SEV";
        }
      ];

      systemd.services.benefice.serviceConfig.LimitMEMLOCK = "8G";
      systemd.services.benefice.serviceConfig.SupplementaryGroups = [config.hardware.cpu.amd.sev.group];
    })
  ]);
}
