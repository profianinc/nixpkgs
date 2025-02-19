{ lib, buildGoModule, fetchFromGitHub, nixosTests, fetchpatch }:

let
  # The web client verifies, that the server version is a valid datetime string:
  # https://github.com/minio/minio/blob/3a0e7347cad25c60b2e51ff3194588b34d9e424c/browser/app/js/web.js#L51-L53
  #
  # Example:
  #   versionToTimestamp "2021-04-22T15-44-28Z"
  #   => "2021-04-22T15:44:28Z"
  versionToTimestamp = version:
    let
      splitTS = builtins.elemAt (builtins.split "(.*)(T.*)" version) 1;
    in
    builtins.concatStringsSep "" [ (builtins.elemAt splitTS 0) (builtins.replaceStrings [ "-" ] [ ":" ] (builtins.elemAt splitTS 1)) ];
in
buildGoModule rec {
  pname = "minio";
  version = "2022-07-17T15-43-14Z";

  src = fetchFromGitHub {
    owner = "minio";
    repo = "minio";
    rev = "RELEASE.${version}";
    sha256 = "sha256-hQ52fL4Z3RHthHaJXCkKpbebWpq8MxHo4BziokTuJA4=";
  };

  vendorSha256 = "sha256-u36oHqIxMD3HRio9A3tUt6FO1DtAcQDiC/O54ByeNyg=";

  patches = [
    (fetchpatch {
      url = "https://github.com/minio/minio/commit/bc72e4226e669d98c8e0f3eccc9297be9251c692.patch";
      name = "CVE-2022-35919.patch";
      sha256 = "sha256-420jff2B1eZArUs8NncWX6dQMMTGAfF1nNjzbwo6AUI=";
    })
  ];

  doCheck = false;

  subPackages = [ "." ];

  CGO_ENABLED = 0;

  tags = [ "kqueue" ];

  ldflags = let t = "github.com/minio/minio/cmd"; in [
    "-s" "-w" "-X ${t}.Version=${versionToTimestamp version}" "-X ${t}.ReleaseTag=RELEASE.${version}" "-X ${t}.CommitID=${src.rev}"
  ];

  passthru.tests.minio = nixosTests.minio;

  meta = with lib; {
    homepage = "https://www.minio.io/";
    description = "An S3-compatible object storage server";
    changelog = "https://github.com/minio/minio/releases/tag/RELEASE.${version}";
    maintainers = with maintainers; [ eelco bachp ];
    platforms = platforms.unix;
    license = licenses.agpl3Plus;
  };
}
