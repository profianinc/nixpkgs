{ config, options, pkgs, lib, ... }:
with lib;
let
  cfg = config.services.aesmd;
  opt = options.services.aesmd;

  sgx-psw = pkgs.sgx-psw.override { inherit (cfg) debug; };

  aesmdConfigFile = with cfg.settings; pkgs.writeText "aesmd.conf" (
    concatStringsSep "\n" (
      optional (whitelistUrl != null) "whitelist url = ${whitelistUrl}" ++
      optional (proxy != null) "aesm proxy = ${proxy}" ++
      optional (proxyType != null) "proxy type = ${proxyType}" ++
      optional (defaultQuotingType != null) "default quoting type = ${defaultQuotingType}" ++
      # Newline at end of file
      [ "" ]
    )
  );
in
{
  options.services.aesmd = {
    enable = mkEnableOption "Intel's Architectural Enclave Service Manager (AESM) for Intel SGX";
    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to build the PSW package in debug mode.";
    };
    settings = mkOption {
      description = "AESM configuration";
      default = { };
      type = types.submodule {
        options.whitelistUrl = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "http://whitelist.trustedservices.intel.com/SGX/LCWL/Linux/sgx_white_list_cert.bin";
          description = "URL to retrieve authorized Intel SGX enclave signers.";
        };
        options.proxy = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "http://proxy_url:1234";
          description = "HTTP network proxy.";
        };
        options.proxyType = mkOption {
          type = with types; nullOr (enum [ "default" "direct" "manual" ]);
          default = if (cfg.settings.proxy != null) then "manual" else null;
          defaultText = literalExpression ''
            if (config.${opt.settings}.proxy != null) then "manual" else null
          '';
          example = "default";
          description = ''
            Type of proxy to use. The <literal>default</literal> uses the system's default proxy.
            If <literal>direct</literal> is given, uses no proxy.
            A value of <literal>manual</literal> uses the proxy from
            <option>services.aesmd.settings.proxy</option>.
          '';
        };
        options.defaultQuotingType = mkOption {
          type = with types; nullOr (enum [ "ecdsa_256" "epid_linkable" "epid_unlinkable" ]);
          default = null;
          example = "ecdsa_256";
          description = "Attestation quote type.";
        };
      };
    };
    qcnl.settings = mkOption {
      description = "QCNL configuration";
      default = null;
      type = with types; nullOr (submodule {
        options.pccsUrl = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "https://localhost:8081/sgx/certification/v3/";
          description = "PCCS server address.";
        };
        options.useSecureCert = mkOption {
          type = with types; nullOr bool;
          default = null;
          example = false;
          description = "To accept insecure HTTPS certificate, set this option to <literal>false</literal>.";
        };
        options.collateralService = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "https://api.trustedservices.intel.com/sgx/certification/v3/";
          description = ''
            You can use the Intel PCS or another PCCS to get quote verification collateral.

            Retrieval of PCK Certificates will always use the PCCS described in <literal>config.services.aesmd.qcnl.settings.pccsUrl</literal>.

            When <literal>null</literal>, both PCK Certs and verification collateral will be retrieved using <literal>config.services.aesmd.qcnl.settings.pccsUrl</literal>.
          '';
        };
        options.pccsApiVersion = mkOption {
          type = with types; nullOr (enum [ "3.0" "3.1" ]);
          default = null;
          example = "3.1";
          description = ''
            If you use a PCCS service to get the quote verification collateral, you can specify which PCCS API version is to be used.

            The legacy 3.0 API will return CRLs in HEX encoded DER format and the sgx_ql_qve_collateral_t.version will be set to 3.0, while
            the new 3.1 API will return raw DER format and the <literal>sgx_ql_qve_collateral_t.version</literal> will be set to 3.1.

            This setting is ignored if <literal>config.services.aesmd.qcnl.settings.collateralService</literal> is set to the Intel PCS.
            In this case, the PCCS API version is forced to be 3.1 internally.

            Currently, only values of <literal>"3.0"</literal> and <literal>"3.1"</literal> are valid.
            Note, if you set this to <literal>"3.1"</literal>, the PCCS used to retrieve verification collateral must support the new 3.1 APIs.
          '';
        };
        options.retryTimes = mkOption {
          type = with types; nullOr ints.u32;
          default = null;
          example = 6;
          description = ''
            Maximum retry times for QCNL. When <literal>null</literal> or set to <literal>0</literal>, no retry will be performed.

            It will first wait one second and then for all forthcoming retries it will double the waiting time.

            By using <literal>config.services.aesmd.qcnl.settings.retryDelay</literal> you disable this exponential backoff algorithm.
          '';
        };
        options.retryDelay = mkOption {
          type = with types; nullOr ints.u32;
          default = null;
          example = 10;
          description = ''
            Sleep this amount of seconds before each retry when a transfer has failed with a transient error.
          '';
        };
        options.localPckUrl = mkOption {
          type = with types; nullOr str;
          default = null;
          example = "http://localhost:8081/sgx/certification/v3/";
          description = ''
            When not <literal>null</literal>, the QCNL will try to retrieve PCK cert chain from this URL first,
            and failover to <literal>config.services.aesmd.qcnl.settings.pccsUrl</literal> as in legacy mode.
          '';
        };
        options.pckCacheExpireHours = mkOption {
          type = with types; nullOr ints.u32;
          default = null;
          example = 168;
          description = ''
            If <literal>config.services.aesmd.qcnl.settings.localPckUrl</literal> is <literal>null</literal>, the QCNL will cache PCK certificates in memory by default.
            The cached PCK certificates will expire after this many hours.
          '';
        };
        options.customRequestOptions = mkOption {
          type = with types; nullOr attrs;
          default = null;
          example = {
            get_cert = {
              headers = {
                head1 = "value1";
              };
              params = {
                param1 = "value1";
                param2 = "value2";
              };
            };
          };
          description = ''
            You can add custom request headers and parameters to the get certificate API.
            But the default PCCS implementation just ignores them.
          '';
        };
      });
    };
  };

  config = mkIf cfg.enable {
    assertions = [{
      assertion = !(config.boot.specialFileSystems."/dev".options ? "noexec");
      message = "SGX requires exec permission for /dev";
    }];

    hardware.cpu.intel.sgx.provision.enable = true;

    # Make sure the AESM service can find the SGX devices until
    # https://github.com/intel/linux-sgx/issues/772 is resolved
    # and updated in nixpkgs.
    hardware.cpu.intel.sgx.enableDcapCompat = mkForce true;

    systemd.services.aesmd =
      let
        storeAesmFolder = "${sgx-psw}/aesm";
        # Hardcoded path AESM_DATA_FOLDER in psw/ae/aesm_service/source/oal/linux/aesm_util.cpp
        aesmDataFolder = "/var/opt/aesmd/data";
        aesmStateDirSystemd = "%S/aesmd";
      in
      {
        description = "Intel Architectural Enclave Service Manager";
        wantedBy = [ "multi-user.target" ];

        after = [
          "auditd.service"
          "network.target"
          "syslog.target"
        ];

        environment = {
          NAME = "aesm_service";
          AESM_PATH = storeAesmFolder;
          LD_LIBRARY_PATH = storeAesmFolder;
        };

        # Make sure any of the SGX application enclave devices is available
        unitConfig.AssertPathExists = [
          # legacy out-of-tree driver
          "|/dev/isgx"
          # DCAP driver
          "|/dev/sgx/enclave"
          # in-tree driver
          "|/dev/sgx_enclave"
        ];

        serviceConfig = rec {
          ExecStartPre = pkgs.writeShellScript "copy-aesmd-data-files.sh" ''
            set -euo pipefail
            whiteListFile="${aesmDataFolder}/white_list_cert_to_be_verify.bin"
            if [[ ! -f "$whiteListFile" ]]; then
              ${pkgs.coreutils}/bin/install -m 644 -D \
                "${storeAesmFolder}/data/white_list_cert_to_be_verify.bin" \
                "$whiteListFile"
            fi
          '';
          ExecStart = "${sgx-psw}/bin/aesm_service --no-daemon";
          ExecReload = ''${pkgs.coreutils}/bin/kill -SIGHUP "$MAINPID"'';

          Restart = "on-failure";
          RestartSec = "15s";

          DynamicUser = true;
          Group = "sgx";
          SupplementaryGroups = [
            config.hardware.cpu.intel.sgx.provision.group
          ];

          Type = "simple";

          WorkingDirectory = storeAesmFolder;
          StateDirectory = "aesmd";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "aesmd";
          RuntimeDirectoryMode = "0750";

          # Hardening

          # chroot into the runtime directory
          RootDirectory = "%t/aesmd";
          BindReadOnlyPaths = [
            builtins.storeDir
            # Hardcoded path AESM_CONFIG_FILE in psw/ae/aesm_service/source/utils/aesm_config.cpp
            "${aesmdConfigFile}:/etc/aesmd.conf"
          ]
            # Hardcoded path in qcnl https://github.com/intel/SGXDataCenterAttestationPrimitives/blob/68a77a852cd911a44a97733aec870e9bd93a3b86/QuoteGeneration/qcnl/linux/qcnl_config_impl.cpp#L112
          ++ optional (!isNull cfg.qcnl.settings) (let
            toSnakeCase = replaceStrings upperChars (map (s: "_${s}") lowerChars);
            qcnlConfig = builtins.toJSON (mapAttrs' (name: value: nameValuePair (toSnakeCase name) value) (filterAttrs (n: v: !isNull v) cfg.qcnl.settings));
            qcnlConfigFile = pkgs.writeText "sgx_default_qcnl.conf" qcnlConfig;
          in
            "${qcnlConfigFile}:/etc/sgx_default_qcnl.conf"
          );
          BindPaths = [
            # Hardcoded path CONFIG_SOCKET_PATH in psw/ae/aesm_service/source/core/ipc/SocketConfig.h
            "%t/aesmd:/var/run/aesmd"
            "%S/aesmd:/var/opt/aesmd"
          ];

          # PrivateDevices=true will mount /dev noexec which breaks AESM
          PrivateDevices = false;
          DevicePolicy = "closed";
          DeviceAllow = [
            # legacy out-of-tree driver
            "/dev/isgx rw"
            # DCAP driver
            "/dev/sgx rw"
            # in-tree driver
            "/dev/sgx_enclave rw"
            "/dev/sgx_provision rw"
          ];

          # Requires Internet access for attestation
          PrivateNetwork = false;

          RestrictAddressFamilies = [
            # Allocates the socket /var/run/aesmd/aesm.socket
            "AF_UNIX"
            # Uses the HTTP protocol to initialize some services
            "AF_INET"
            "AF_INET6"
          ];

          # True breaks stuff
          MemoryDenyWriteExecute = false;

          # needs the ipc syscall in order to run
          SystemCallFilter = [
            "@system-service"
            "~@aio"
            "~@chown"
            "~@clock"
            "~@cpu-emulation"
            "~@debug"
            "~@keyring"
            "~@memlock"
            "~@module"
            "~@mount"
            "~@privileged"
            "~@raw-io"
            "~@reboot"
            "~@resources"
            "~@setuid"
            "~@swap"
            "~@sync"
            "~@timer"
          ];
          SystemCallArchitectures = "native";
          SystemCallErrorNumber = "EPERM";

          CapabilityBoundingSet = "";
          KeyringMode = "private";
          LockPersonality = true;
          NoNewPrivileges = true;
          NotifyAccess = "none";
          PrivateMounts = true;
          PrivateTmp = true;
          PrivateUsers = true;
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          ProtectSystem = "strict";
          RemoveIPC = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          UMask = "0066";
        };
      };
  };
}
