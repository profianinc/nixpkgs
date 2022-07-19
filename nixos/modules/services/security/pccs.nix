{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.pccs;

  backend = config.virtualisation.oci-containers.backend;

  pccsService = "${backend}-pccs";

  pccsImageName = "registry.gitlab.com/haraldh/pccs";
  pccs = pkgs.dockerTools.pullImage {
    imageName = pccsImageName;
    imageDigest = "sha256:b0729c0588a124c23d1c8d53d1ccd4f3d4ac099afc46e3fa8e5e0da9738bc760";
    sha256 = "0xgxq82j3x2j21m2xzq5rwckn28n9ym6cfivaxadry6a9wpi40xr";
    finalImageTag = "working";
  };
in
  with lib; {
    options.services.pccs = {
      enable = mkEnableOption "Intel SGX Provisioning Certification service.";
      apiKeyFile = mkOption {
        type = types.str;
        description = "Path to SGX API key file.";
      };
    };

    config = mkMerge [
      (mkIf cfg.enable {
        systemd.services.${pccsService} = {
          preStart = "${backend} secret create PCCS_APIKEY ${cfg.apiKeyFile}";
          postStop = "${backend} secret rm PCCS_APIKEY";
          serviceConfig.Restart = "always";
          serviceConfig.Type = "exec";
        };

        virtualisation.oci-containers.containers.pccs.extraOptions = [
          "--network=host"
          "--secret=PCCS_APIKEY,type=mount"
        ];
        virtualisation.oci-containers.containers.pccs.image = pccsImageName;
        virtualisation.oci-containers.containers.pccs.imageFile = pccs;
      })
    ];
  }
