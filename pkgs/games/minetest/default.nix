{ lib
, stdenv
, fetchFromGitHub
, cmake
, irrlichtmt
, coreutils
, libpng
, bzip2
, curl
, libogg
, jsoncpp
, libjpeg
, libXxf86vm
, libGLU
, libGL
, openal
, libvorbis
, sqlite
, luajit
, freetype
, gettext
, doxygen
, ncurses
, graphviz
, xorg
, gmp
, libspatialindex
, leveldb
, postgresql
, hiredis
, libiconv
, zlib
, libXrandr
, libX11
, ninja
, prometheus-cpp
, OpenGL
, OpenAL ? openal
, Carbon
, Cocoa
, withTouchSupport ? false
}:

with lib;

let
  boolToCMake = b: if b then "ON" else "OFF";

  irrlichtmtInput = irrlichtmt.override { inherit withTouchSupport; };

  generic = { version, rev ? version, sha256, dataRev ? version, dataSha256, buildClient ? true, buildServer ? false }: let
    sources = {
      src = fetchFromGitHub {
        owner = "minetest";
        repo = "minetest";
        inherit rev sha256;
      };
      data = fetchFromGitHub {
        owner = "minetest";
        repo = "minetest_game";
        rev = dataRev;
        sha256 = dataSha256;
      };
    };
  in stdenv.mkDerivation {
    pname = "minetest";
    inherit version;

    src = sources.src;

    cmakeFlags = [
      "-G Ninja"
      "-DBUILD_CLIENT=${boolToCMake buildClient}"
      "-DBUILD_SERVER=${boolToCMake buildServer}"
      "-DENABLE_GETTEXT=1"
      "-DENABLE_SPATIAL=1"
      "-DENABLE_SYSTEM_JSONCPP=1"
      "-DIRRLICHT_INCLUDE_DIR=${irrlichtmtInput.dev}/include/irrlichtmt"

      # Remove when https://github.com/NixOS/nixpkgs/issues/144170 is fixed
      "-DCMAKE_INSTALL_BINDIR=bin"
      "-DCMAKE_INSTALL_DATADIR=share"
      "-DCMAKE_INSTALL_DOCDIR=share/doc"
      "-DCMAKE_INSTALL_DOCDIR=share/doc"
      "-DCMAKE_INSTALL_MANDIR=share/man"
      "-DCMAKE_INSTALL_LOCALEDIR=share/locale"

    ] ++ optionals buildClient [
      "-DOpenGL_GL_PREFERENCE=GLVND"
    ] ++ optionals buildServer [
      "-DENABLE_PROMETHEUS=1"
    ] ++ optionals withTouchSupport [
      "-DENABLE_TOUCH=TRUE"
    ];

    NIX_CFLAGS_COMPILE = "-DluaL_reg=luaL_Reg"; # needed since luajit-2.1.0-beta3

    nativeBuildInputs = [ cmake doxygen graphviz ninja ];

    buildInputs = [
      irrlichtmtInput luajit jsoncpp gettext freetype sqlite curl bzip2 ncurses
      gmp libspatialindex
    ] ++ optionals stdenv.isDarwin [
      libiconv OpenGL OpenAL Carbon Cocoa
    ] ++ optionals buildClient [
      libpng libjpeg libGLU libGL openal libogg libvorbis xorg.libX11 libXxf86vm
    ] ++ optionals buildServer [
      leveldb postgresql hiredis prometheus-cpp
    ];

    postPatch = ''
      substituteInPlace src/filesys.cpp --replace "/bin/rm" "${coreutils}/bin/rm"
    '';

    postInstall = ''
      mkdir -pv $out/share/minetest/games/minetest_game/
      cp -rv ${sources.data}/* $out/share/minetest/games/minetest_game/
      patchShebangs $out
    '';

    meta = with lib; {
      homepage = "http://minetest.net/";
      description = "Infinite-world block sandbox game";
      license = licenses.lgpl21Plus;
      platforms = platforms.linux ++ platforms.darwin;
      maintainers = with maintainers; [ pyrolagus fpletz fgaz ];
      # https://github.com/NixOS/nixpkgs/pull/186160#issuecomment-1212635918
      broken = stdenv.isDarwin;
    };
  };

  v5 = {
    version = "5.6.1";
    sha256 = "sha256-1mUmtM09jqJhD2RcLCAjaI+JkqP52QYH3KLkY5MZ860=";
    dataSha256 = "sha256-Ye8MihrOqjSoy+vNr/CM/C/sNXdexe08dxrmoMxsG/A=";
  };

  mkClient = version: generic (version // { buildClient = true; buildServer = false; });
  mkServer = version: generic (version // { buildClient = false; buildServer = true; });
in {
  minetestclient_5 = mkClient v5;
  minetestserver_5 = mkServer v5;
}
