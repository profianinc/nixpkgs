{ lib
, stdenv
, runtimeShell
, fetchurl
, autoPatchelfHook
, wrapGAppsHook
, dpkg
, atomEnv
, libuuid
, libappindicator-gtk3
, pulseaudio
, at-spi2-atk
, coreutils
, gawk
, xdg-utils
, systemd
, nodePackages
, xar
, cpio
, makeWrapper
, enableRectOverlay ? false
}:

let
  pname = "teams";
  versions = {
    linux = "1.5.00.23861";
    darwin = "1.5.00.22362";
  };
  hashes = {
    linux = "sha256-h0YnCeJX//l4TegJVZtavV3HrxjYUF2Fa5KmaYmZW8E=";
    darwin = "sha256-fbw6T+k6R5FyQ7XOKzyNYBvXlxH2xpJsBnsR1L+3Jmw=";
  };
  meta = with lib; {
    description = "Microsoft Teams";
    homepage = "https://teams.microsoft.com";
    downloadPage = "https://teams.microsoft.com/downloads";
    license = licenses.unfree;
    maintainers = with maintainers; [ liff tricktron ];
    platforms = [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };

  linux = stdenv.mkDerivation rec {
    inherit pname meta;
    version = versions.linux;

    src = fetchurl {
      url = "https://packages.microsoft.com/repos/ms-teams/pool/main/t/teams/teams_${versions.linux}_amd64.deb";
      hash = hashes.linux;
    };

    nativeBuildInputs = [ dpkg autoPatchelfHook wrapGAppsHook nodePackages.asar ];

    unpackCmd = "dpkg -x $curSrc .";

    buildInputs = atomEnv.packages ++ [
      libuuid
      at-spi2-atk
    ];

    runtimeDependencies = [
      (lib.getLib systemd)
      pulseaudio
      libappindicator-gtk3
    ];

    preFixup = ''
      gappsWrapperArgs+=(--prefix PATH : "${coreutils}/bin:${gawk}/bin")
    '';


    buildPhase = ''
      runHook preBuild

      asar extract share/teams/resources/app.asar "$TMP/work"
      substituteInPlace $TMP/work/main.bundle.js \
          --replace "/usr/share/pixmaps/" "$out/share/pixmaps" \
          --replace "/usr/bin/xdg-mime" "${xdg-utils}/bin/xdg-mime" \
          --replace "Exec=/usr/bin/" "Exec=" # Remove usage of absolute path in autostart.
      asar pack --unpack='{*.node,*.ftz,rect-overlay}' "$TMP/work" share/teams/resources/app.asar

      runHook postBuild
    '';

    preferLocalBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/{opt,bin}

      mv share/teams $out/opt/
      mv share $out/share

      substituteInPlace $out/share/applications/teams.desktop \
        --replace /usr/bin/ ""

      ln -s $out/opt/teams/teams $out/bin/

      ${lib.optionalString (!enableRectOverlay) ''
      # Work-around screen sharing bug
      # https://docs.microsoft.com/en-us/answers/questions/42095/sharing-screen-not-working-anymore-bug.html
      rm $out/opt/teams/resources/app.asar.unpacked/node_modules/slimcore/bin/rect-overlay
      ''}

      runHook postInstall
    '';

    dontAutoPatchelf = true;

    # Includes runtimeDependencies in the RPATH of the included Node modules
    # so that dynamic loading works. We cannot use directly runtimeDependencies
    # here, since the libraries from runtimeDependencies are not propagated
    # to the dynamically loadable node modules because of a condition in
    # autoPatchElfHook since *.node modules have Type: DYN (Shared object file)
    # instead of EXEC or INTERP it expects.
    # Fixes: https://github.com/NixOS/nixpkgs/issues/85449
    postFixup = ''
      autoPatchelf "$out"

      runtime_rpath="${lib.makeLibraryPath runtimeDependencies}"

      for mod in $(find "$out/opt/teams" -name '*.node'); do
        mod_rpath="$(patchelf --print-rpath "$mod")"

        echo "Adding runtime dependencies to RPATH of Node module $mod"
        patchelf --set-rpath "$runtime_rpath:$mod_rpath" "$mod"
      done;

      # fix for https://docs.microsoft.com/en-us/answers/questions/298724/open-teams-meeting-link-on-linux-doens39t-work.html?childToView=309406#comment-309406
      wrapped=$out/bin/.teams-old
      mv "$out/bin/teams" "$wrapped"
      cat > "$out/bin/teams" << EOF
      #! ${runtimeShell}
      exec $wrapped "\$@" --disable-namespace-sandbox --disable-setuid-sandbox
      EOF
      chmod +x "$out/bin/teams"
    '';
  };

  appName = "Teams.app";

  darwin = stdenv.mkDerivation {
    inherit pname meta;
    version = versions.darwin;

    src = fetchurl {
      url = "https://statics.teams.cdn.office.net/production-osx/${versions.darwin}/Teams_osx.pkg";
      hash = hashes.darwin;
    };

    buildInputs = [ xar cpio makeWrapper ];

    unpackPhase = ''
      xar -xf $src
      zcat < Teams_osx_app.pkg/Payload | cpio -i
    '';

    sourceRoot = "Microsoft\ Teams.app";
    dontPatch = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/{Applications/${appName},bin}
      cp -R . $out/Applications/${appName}
      makeWrapper $out/Applications/${appName}/Contents/MacOS/Teams $out/bin/teams
      runHook postInstall
    '';
  };
in
if stdenv.isDarwin
then darwin
else linux
