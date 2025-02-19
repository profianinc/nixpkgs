{ lib
, stdenv
, fetchFromGitHub
, fetchpatch
, autoreconfHook
, perl
, withDebug ? false
}:

stdenv.mkDerivation rec {
  pname = "tinyproxy";
  version = "1.11.0";

  src = fetchFromGitHub {
    sha256 = "13fhkmmrwzl657dq04x2wagkpjwdrzhkl141qvzr7y7sli8j0w1n";
    rev = version;
    repo = "tinyproxy";
    owner = "tinyproxy";
  };

  patches = [
    (fetchpatch {
      name = "CVE-2022-40468.patch";
      url = "https://github.com/tinyproxy/tinyproxy/commit/3764b8551463b900b5b4e3ec0cd9bb9182191cb7.patch";
      sha256 = "sha256-P0c4mUK227ld3703ss5MQhi8Vo2QVTCVXhKmc9fcufk=";
    })
  ];

  # perl is needed for man page generation.
  nativeBuildInputs = [ autoreconfHook perl ];

  configureFlags = lib.optionals withDebug [ "--enable-debug" ]; # Enable debugging support code and methods.

  meta = with lib; {
    broken = stdenv.isDarwin;
    homepage = "https://tinyproxy.github.io/";
    description = "A light-weight HTTP/HTTPS proxy daemon for POSIX operating systems";
    license = licenses.gpl2Only;
    platforms = platforms.all;
    maintainers = [ maintainers.carlosdagos ];
  };
}
