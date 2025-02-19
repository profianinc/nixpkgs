{ stdenv
, fetchFromGitLab
, cmake
, ninja
, pkg-config
, boost
, glib
, gsl
, cairo
, double-conversion
, gtest
, lib
}:

stdenv.mkDerivation rec {
  pname = "lib2geom";
  version = "1.1";

  outputs = [ "out" "dev" ];

  src = fetchFromGitLab {
    owner = "inkscape";
    repo = "lib2geom";
    rev = "refs/tags/${version}";
    sha256 = "sha256-u9pbpwVzAXzrM2/tQnd1B6Jo9Fzg6UZBr9AtUsNMfQ0=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    boost
    glib
    gsl
    cairo
    double-conversion
  ];

  checkInputs = [
    gtest
  ];

  cmakeFlags = [
    "-DCMAKE_SKIP_BUILD_RPATH=OFF" # for tests
    "-D2GEOM_BUILD_SHARED=ON"
  ];

  doCheck = true;

  meta = with lib; {
    description = "Easy to use 2D geometry library in C++";
    homepage = "https://gitlab.com/inkscape/lib2geom";
    license = [ licenses.lgpl21Only licenses.mpl11 ];
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };
}
