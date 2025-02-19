{ stdenv, lib, fetchurl, glibc, zlib
, enableStatic ? stdenv.hostPlatform.isStatic
, sftpPath ? "/run/current-system/sw/libexec/sftp-server"
, fetchpatch
}:

stdenv.mkDerivation rec {
  pname = "dropbear";
  version = "2020.81";

  src = fetchurl {
    url = "https://matt.ucc.asn.au/dropbear/releases/dropbear-${version}.tar.bz2";
    sha256 = "0fy5ma4cfc2pk25mcccc67b2mf1rnb2c06ilb7ddnxbpnc85s8s8";
  };

  dontDisableStatic = enableStatic;

  configureFlags = lib.optional enableStatic "LDFLAGS=-static";

  CFLAGS = "-DSFTPSERVER_PATH=\\\"${sftpPath}\\\"";

  # https://www.gnu.org/software/make/manual/html_node/Libraries_002fSearch.html
  preConfigure = ''
    makeFlags=VPATH=`cat $NIX_CC/nix-support/orig-libc`/lib
  '';

  patches = [
    # Allow sessions to inherit the PATH from the parent dropbear.
    # Otherwise they only get the usual /bin:/usr/bin kind of PATH
    ./pass-path.patch
    (fetchpatch {
      url = "https://github.com/mkj/dropbear/commit/210a9833496ed2a93b8da93924874938127ce0b5.patch";
      sha256 = "sha256-ufnE+2uTsG23m+a/LwHfOEPZ3mq53vdFktZrVFH3yk4=";
      name = "CVE-2021-36369.patch";
    })
  ];

  buildInputs = [ zlib ] ++ lib.optionals enableStatic [ glibc.static zlib.static ];

  meta = with lib; {
    homepage = "https://matt.ucc.asn.au/dropbear/dropbear.html";
    description = "A small footprint implementation of the SSH 2 protocol";
    license = licenses.mit;
    maintainers = with maintainers; [ abbradar ];
    platforms = platforms.linux;
  };
}
