{
  description = "Native cliche binary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cliche = { url = "github:nbd-wtf/cliche"; flake = false; };
    immortan = { url = "github:fiatjaf/immortan"; flake = false; };
    graal = { url = "https://github.com/gluonhq/graal/releases/download/gluon-22.0.0.3-Final/graalvm-svm-java11-linux-gluon-22.0.0.3-Final.zip"; flake = false; };
    sbt = { url = "https://github.com/sbt/sbt/releases/download/v1.6.2/sbt-1.6.2.tgz"; flake = false; };
  };

  outputs = { self, nixpkgs, cliche, immortan, graal, sbt }:
    {
      packages = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system:
        let
          pkgs = import nixpkgs { inherit system; };

          commonNativeBuildInputs = with pkgs; [ bash gcc gnumake perl python3 file unzip patchelf autoPatchelfHook ];
          commonBuildInputs = with pkgs; [
            zlib glibc stdenv.cc.cc.lib
            libxext libx11 libxrender libxtst libxi freetype alsa-lib
          ];

          setupTools = ''
            mkdir -p "$TMPDIR/graal-unpacked" "$TMPDIR/sbt-unpacked"
            if [ -f ${graal} ]; then
              unzip -q ${graal} -d "$TMPDIR/graal-unpacked"
            else
              cp -R ${graal}/. "$TMPDIR/graal-unpacked/"
            fi
            chmod -R u+w "$TMPDIR/graal-unpacked"
            autoPatchelf "$TMPDIR/graal-unpacked"
            export JAVA_HOME=$(find "$TMPDIR/graal-unpacked" -type f -path '*/bin/java' -printf '%h/..\n' | head -1)
            export GRAALVM_HOME="$JAVA_HOME"

            if [ -f ${sbt} ]; then
              tar -xzf ${sbt} -C "$TMPDIR/sbt-unpacked"
            else
              cp -R ${sbt}/. "$TMPDIR/sbt-unpacked/"
            fi
            chmod -R u+w "$TMPDIR/sbt-unpacked"
            export PATH="$JAVA_HOME/bin:$(find "$TMPDIR/sbt-unpacked" -type d -name bin | head -1):$PATH"
            sed -i '1c#!${pkgs.bash}/bin/bash' "$(command -v sbt)"
            chmod +x "$(command -v sbt)"
            export SBT_HOME=$(dirname "$(dirname "$(command -v sbt)")")
            # Keep all SBT/Ivy/Coursier state in one directory that can be
            # captured by the fixed-output deps derivation and restored for the
            # offline final build.
            export HOME="$TMPDIR"
            export COURSIER_CACHE="$HOME/.cache/coursier"
            export SBT_OPTS="-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+UseG1GC -Dsbt.boot.directory=$HOME/.sbt/boot -Dsbt.global.base=$HOME/.sbt -Dsbt.ivy.home=$HOME/.ivy2 -Divy.home=$HOME/.ivy2 -Dsbt.coursier.home=$COURSIER_CACHE"
            mkdir -p "$HOME" "$COURSIER_CACHE"
          '';

          patchCliche = ''
            rm -f native-image-configs/serialization-config.json
            python3 -c 'import json; from pathlib import Path; p=Path("native-image-configs/resource-config.json"); d=json.loads(p.read_text()); i=d["resources"]["includes"]; e={x.get("pattern") for x in i}; [i.append({"pattern": x}) for x in [r"\Qelectrum/checkpoints_testnet.json\E", r"\Qelectrum/servers_testnet.json\E"] if x not in e]; p.write_text(json.dumps(d, indent=2)+chr(10))'
          '';

          # SBT/Maven dependencies are not GitHub sources and are normally
          # downloaded by sbt.  Put them in a fixed-output derivation so Nix may
          # fetch them once, hash the resulting cache, then reuse it offline.
          sbtDeps = pkgs.stdenv.mkDerivation {
            pname = "cliche-sbt-deps";
            version = "unstable";
            nativeBuildInputs = commonNativeBuildInputs;
            buildInputs = commonBuildInputs;
            dontUnpack = true;
            outputHashMode = "recursive";
            outputHashAlgo = "sha256";
            # First build will intentionally fail and print the real hash.
            # Replace this value with the printed sha256, then run nix build again.
            outputHash = "sha256-PJGBfsZ3VHNBDnkg0j1xTGmnpNRAlcvkWFrYQYfZE8s=";
            buildPhase = ''
              ${setupTools}
              cp -R ${immortan} "$TMPDIR/immortan"
              chmod -R u+w "$TMPDIR/immortan"
              cd "$TMPDIR/immortan"
              perl -i -0pe 's/.*sonatype.*\n//g' build.sbt
              sbt publishLocal update compile

              cp -R ${cliche} "$TMPDIR/cliche"
              chmod -R u+w "$TMPDIR/cliche"
              cd "$TMPDIR/cliche"
              ${patchCliche}
              # `update` is not enough: the final nativeImage task compiles
              # Scala and needs the Zinc compiler bridge sources/jars in the
              # offline cache.
              sbt update compile
            '';
            installPhase = ''
              mkdir -p $out
              cp -R "$HOME/.ivy2" "$HOME/.sbt" "$HOME/.cache" $out/ 2>/dev/null || true
            '';
          };
        in rec {
          deps = sbtDeps;

          default = pkgs.stdenv.mkDerivation {
            pname = "cliche";
            version = "unstable";
            src = cliche;
            nativeBuildInputs = commonNativeBuildInputs;
            buildInputs = commonBuildInputs;
            preBuild = ''
              ${setupTools}
              cp -R ${sbtDeps}/. "$HOME/" || true
              chmod -R u+w "$HOME"

              cp -R ${immortan} "$TMPDIR/immortan"
              chmod -R u+w "$TMPDIR/immortan"
              cd "$TMPDIR/immortan"
              perl -i -0pe 's/.*sonatype.*\n//g' build.sbt
              sbt publishLocal
              cd "$NIX_BUILD_TOP/source"
              ${patchCliche}
            '';
            buildPhase = ''
              runHook preBuild
              sbt nativeImage
            '';
            installPhase = ''
              install -Dm755 target/native-image/cliche $out/bin/cliche
            '';
          };
        });
    };
}
