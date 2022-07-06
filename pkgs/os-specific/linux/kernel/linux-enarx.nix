# Adapted from linux-testing
{ lib, fetchurl, buildLinux, ... } @ args:

with lib;

buildLinux (args // rec {
  version = "5.18-rc3-enarx-2";
  modDirVersion = "5.18.0-rc3-next-20220422";
  extraMeta.branch = lib.versions.majorMinor version;

  src = fetchurl {
    url = "https://github.com/enarx/linux/archive/refs/tags/v${version}.tar.gz";
    sha256 = "sha256-Mjlag+8ijiwaY6VjhVkDNtbnxnTBnsHERGa99J5gKg0=";
  };

  # Config required for SGX and SEV-SNP and a few options from Debian.
  structuredExtraConfig = with lib.kernel; {
    AMD_IOMMU_V2 = yes;
    AMD_MEM_ENCRYPT = yes;
    CRYPTO_DEV_CCP = yes;
    CRYPTO_DEV_CCP_CRYPTO = module;
    CRYPTO_DEV_CCP_DD = module;
    CRYPTO_DEV_SP_CCP = yes;
    CRYPTO_DEV_SP_PSP = yes;
    INIT_ON_ALLOC_DEFAULT_ON = yes;
    INTEGRITY_ASYMMETRIC_KEYS = yes;
    INTEGRITY_SIGNATURE = yes;
    INTEL_IOMMU_SVM = yes;
    INTEL_TURBO_MAX_3 = yes;
    INTEL_TXT = yes;
    KVM_AMD_SEV = yes;
    MODULE_COMPRESS_NONE = yes;
    MODULE_COMPRESS_XZ = lib.mkForce no;
    MODVERSIONS = yes;
    PACKET = yes;
    SECURITY_DMESG_RESTRICT = yes;
    SECURITY_NETWORK_XFRM=yes;
    SEV_GUEST = yes;
    X86_CPU_RESCTRL = yes;
    X86_SGX = yes;
    X86_SGX_KVM = yes;
  };
 } // (args.argsOverride or {}))
