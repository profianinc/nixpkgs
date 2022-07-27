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
    };
  };

  config = let
    # Adapted from https://github.com/rapiz1/rathole/tree/ef154cb56ba87509c1879b72fcfd6708e1563d67/examples/systemd
    mkService = description: args: {
      inherit description;
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${pkgs.rathole}/bin/rathole ${args}";
        LimitNOFILE = 1048576;
        Restart = "on-failure";
        RestartSec = "5s";
        Type = "exec";
      };
    };
  in
    mkIf cfg.enable {
      environment.systemPackages = with pkgs; [rathole];

      systemd.services."rathole@" = mkService "Rathole service" "/etc/rathole/%i";
      systemd.services."ratholec@" = mkService "Rathole Client service" "-c /etc/rathole/%i";
      systemd.services."ratholes@" = mkService "Rathole Server service" "-s /etc/rathole/%i";
    };
}
