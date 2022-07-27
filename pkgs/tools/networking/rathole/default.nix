{
  CoreServices,
  Security,
  fetchFromGitHub,
  lib,
  openssl,
  pkg-config,
  rustPlatform,
  stdenv,
}:
rustPlatform.buildRustPackage rec {
  pname = "rathole";
  version = "0.4.2";

  src = fetchFromGitHub {
    owner = "rapiz1";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-fcQBafqyE/274QZ7AmivAE4xEQOBBMVqrMySBXBmxnA=";
  };

  cargoSha256 = "sha256-ImBx2wKZzEXWxNvfu/2Dj/cyY3v5GZNwsPM3XM1Otxg=";

  buildInputs =
    [
      openssl
    ]
    ++ lib.optionals stdenv.isDarwin [
      CoreServices
      Security
    ];
  nativeBuildInputs = [pkg-config];

  meta = with lib; {
    description = "A lightweight and high-performance reverse proxy for NAT traversal, written in Rust. An alternative to frp and ngrok.";
    homepage = "https://github.com/rapiz1/rathole";
    license = with licenses; [asl20];
    maintainers = with maintainers; [rvolosatovs];
  };
}
