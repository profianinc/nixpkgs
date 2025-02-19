{ fetchurl, fetchpatch, lib, stdenv, pkg-config, libdaemon, dbus, perlPackages
, expat, gettext, intltool, glib, libiconv, writeShellScriptBin, libevent
, nixosTests
, gtk3Support ? false, gtk3 ? null
, qt4 ? null
, qt4Support ? false
, qt5 ? null
, qt5Support ? false
, withLibdnssdCompat ? false
, python ? null
, withPython ? false }:

assert qt4Support -> qt4 != null;

let
  # despite the configure script claiming it supports $PKG_CONFIG, it doesnt respect it
  pkg-config-helper = writeShellScriptBin "pkg-config" ''exec $PKG_CONFIG "$@"'';
in

stdenv.mkDerivation rec {
  pname = "avahi${lib.optionalString withLibdnssdCompat "-compat"}";
  version = "0.8";

  src = fetchurl {
    url = "https://github.com/lathiat/avahi/releases/download/v${version}/avahi-${version}.tar.gz";
    sha256 = "1npdixwxxn3s9q1f365x9n9rc5xgfz39hxf23faqvlrklgbhj0q6";
  };

  prePatch = ''
    substituteInPlace configure \
      --replace pkg-config "$PKG_CONFIG"
  '';

  patches = [
    ./no-mkdir-localstatedir.patch
    # CVE-2021-36217 / CVE-2021-3502
    (fetchpatch {
      url = "https://github.com/lathiat/avahi/commit/9d31939e55280a733d930b15ac9e4dda4497680c.patch";
      sha256 = "sha256-BXWmrLWUvDxKPoIPRFBpMS3T4gijRw0J+rndp6iDybU=";
    })
    # CVE-2021-3468
    (fetchpatch {
      url = "https://github.com/lathiat/avahi/commit/447affe29991ee99c6b9732fc5f2c1048a611d3b.patch";
      sha256 = "sha256-qWaCU1ZkCg2PmijNto7t8E3pYRN/36/9FrG8okd6Gu8=";
    })
  ];

  buildInputs = [ libdaemon dbus glib expat libiconv libevent ]
    ++ (with perlPackages; [ perl XMLParser ])
    ++ (lib.optional gtk3Support gtk3)
    ++ (lib.optional qt4Support qt4)
    ++ (lib.optional qt5Support qt5);

  propagatedBuildInputs =
    lib.optionals withPython (with python.pkgs; [ python pygobject3 dbus-python ]);

  nativeBuildInputs = [ pkg-config pkg-config-helper gettext intltool glib ];

  configureFlags =
    [ "--disable-qt3" "--disable-gdbm" "--disable-mono"
      "--disable-gtk" "--with-dbus-sys=${placeholder "out"}/share/dbus-1/system.d"
      (lib.enableFeature gtk3Support "gtk3")
      "--${if qt4Support then "enable" else "disable"}-qt4"
      "--${if qt5Support then "enable" else "disable"}-qt5"
      (lib.enableFeature withPython "python")
      "--localstatedir=/var" "--with-distro=none"
      # A systemd unit is provided by the avahi-daemon NixOS module
      "--with-systemdsystemunitdir=no" ]
    ++ lib.optional withLibdnssdCompat "--enable-compat-libdns_sd"
    # autoipd won't build on darwin
    ++ lib.optional stdenv.isDarwin "--disable-autoipd";

  NIX_CFLAGS_COMPILE = "-DAVAHI_SERVICE_DIR=\"/etc/avahi/services\"";

  preBuild = lib.optionalString stdenv.isDarwin ''
    sed -i '20 i\
    #define __APPLE_USE_RFC_2292' \
    avahi-core/socket.c
  '';

  postInstall =
    # Maintain compat for mdnsresponder and howl
    lib.optionalString withLibdnssdCompat ''
      ln -s avahi-compat-libdns_sd/dns_sd.h "$out/include/dns_sd.h"
    '';
  /*  # these don't exist (anymore?)
    ln -s avahi-compat-howl $out/include/howl
    ln -s avahi-compat-howl.pc $out/lib/pkgconfig/howl.pc
  */

  passthru.tests = {
    smoke-test = nixosTests.avahi;
    smoke-test-resolved = nixosTests.avahi-with-resolved;
  };

  meta = with lib; {
    description = "mDNS/DNS-SD implementation";
    homepage    = "http://avahi.org";
    license     = licenses.lgpl2Plus;
    platforms   = platforms.unix;
    maintainers = with maintainers; [ lovek323 globin ];

    longDescription = ''
      Avahi is a system which facilitates service discovery on a local
      network.  It is an implementation of the mDNS (for "Multicast
      DNS") and DNS-SD (for "DNS-Based Service Discovery")
      protocols.
    '';
  };
}
