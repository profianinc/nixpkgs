{ fetchurl
, lib
, stdenv
, meson
, ninja
, pkg-config
, gettext
, gtk-doc
, docbook-xsl-nons
, gobject-introspection
, gnome
, libsoup
, json-glib
, glib
, nixosTests
}:

stdenv.mkDerivation rec {
  pname = "geocode-glib";
  version = "3.26.3";

  outputs = [ "out" "dev" "devdoc" "installedTests" ];

  src = fetchurl {
    url = "mirror://gnome/sources/geocode-glib/${lib.versions.majorMinor version}/geocode-glib-${version}.tar.xz";
    sha256 = "Hf6ug7kOzMobbPfc98XjsxeCjPC1YgXERx7w+RGZl2Y=";
  };

  patches = [
    ./installed-tests-path.patch
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gettext
    gtk-doc
    docbook-xsl-nons
    gobject-introspection
  ];

  buildInputs = [
    glib
    libsoup
    json-glib
  ];

  mesonFlags = [
    "-Dsoup2=${lib.boolToString (lib.versionOlder libsoup.version "2.99")}"
    "-Dinstalled_test_prefix=${placeholder "installedTests"}"
  ];

  passthru = {
    updateScript = gnome.updateScript {
      packageName = pname;
    };
    tests = {
      installed-tests = nixosTests.installed-tests.geocode-glib;
    };
  };

  meta = with lib; {
    description = "A convenience library for the geocoding and reverse geocoding using Nominatim service";
    license = licenses.lgpl2Plus;
    maintainers = teams.gnome.members;
    platforms = platforms.linux;
  };
}
