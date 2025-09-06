{
  description = "Enola AI; see https://enola.dev";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    nixpkgs-bun.url = "github:nixos/nixpkgs/ab1f3b61279dfe63cdc938ed90660b99e9d46619"; # bun==1.2.19
    # TODO How-to do this? Or is this not possible?!
    # nix develop: warning: input 'nixpkgs-bun' has an override for a non-existent input 'nixpkgs'
    # nix flake metadata shows that it does not work
    #   nixpkgs-bun.inputs.nixpkgs.follows = "nixpkgs";

    deadnix.url = "github:astro/deadnix";
    deadnix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-bun,
      flake-utils,
      deadnix,
      bazel-flake,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        pkgs-bun = import nixpkgs-bun { inherit system; };
        jdk' = pkgs.jdk21;
        buildTools = with pkgs; [
          # https://github.com/NixOS/nixfmt/issues/335
          nix

          python312
          curl
          git
          go
          jq
          bazel_8
          # TODO Finish switch from Bazelisk to Bazel package
          #   by cleaning up all scripts etc. which still use
          #   bazelisk, and then rm this, and .bazelversion
          bazelisk
          shellcheck
          nixpkgs-fmt
          unzip
          nodejs
          coursier
          jdk'
          graphviz
          protobuf
          protoc-gen-grpc-java
          which

          statix
          deadnix.packages.${system}.default

          pkgs-bun.bun
        ];
        # NB: This doesn't actually use tools/version/version-out.bash (like the non-Nix build does)
        gitRev = toString (self.shortRev or self.dirtyShortRev or self.lastModified or "DEVELOPMENT");

        originalBazel = pkgs.bazel_8; #bazel-flake.packages.${system}.bazel;

        # `buildBazelPackage` expects to call `.override` on the `bazel` attribute.
        # We construct a new attribute set that contains the final derivation's attributes
        # and adds a custom `override` function.
        bazelForBuildBazelPackage = originalBazel // {
          # This override function is called by `buildBazelPackage` with arguments
          # like `{ enableNixHacks = true; }`.
          # It ignores the arguments and simply returns the original derivation.
          # This satisfies the interface required by `buildBazelPackage`.
          override = args: originalBazel;
        };
      in
      {
        # TODO: for https://nix-bazel.build, replace with mkShellNoCC.
        devShells.default = pkgs.mkShell {
          packages = buildTools;

          # Python venv. Warning: impure! We mitigate impurity through
          # specifying exact package versions in requirements.txt
          venvDir = "./.venv";
          postVenvCreation = ''
            pip install -r requirements.txt
          '';
          buildInputs = with pkgs.python312Packages; [
            venvShellHook
          ];

          # A hook run every time you enter the environment
          postShellHook = ''
            # TODO Huh, why is this ugly hack required!?
            export PATH="${pkgs.protoc-gen-grpc-java}/bin:$PATH"

            echo Welcome to contributing to Enola.dev! You can now run e.g. ./enola or ./test.bash etc. here.
          '';
        };

        packages = rec {
          # $ nix run
          # $ nix build .#enola
          # $ result/bin/enola --help
          default = enola;
          enola = pkgs.buildBazelPackage {
            pname = "enola";
            version = gitRev;

            bazelTargets = [ "//java/dev/enola/cli:enola_deploy.jar" ];
            # bazelFetchFlags = [ "--all" ];
            fetchAttrs = {
              preBuild = ''
                echo $bazelOut
                mkdir -p $bazelOut/external/cache
              '';
              sha256 = "sha256-ZWjHxMv3IHdWO9+rhn03WQmfmewtV1PEqGkpckaUcyU=";
              # Some Python stuff...
              preInstall = ''
                chmod -R u+w $bazelOut
              '';
            };

            src = ./.;

            bazel = bazelForBuildBazelPackage;

            removeRulesCC = false;
            removeLocalConfigCc = false;
            removeLocalConfigSh = false;
            removeLocal = false;

            bazelFlags = [ "--distdir=/build/output/external/cache" ];
            fetchConfigured = false;

            bazelBuildFlags = [
              "--verbose_failures"
              "--nofetch"
            ];
            #passthru = {
            #  exePath = "/bin/enola";
            #};
>>>>>>> 8d4ece30 (Does not work)

            buildInputs = [ jdk' ];
            nativeBuildInputs = buildTools ++ [
              #  pkgs.cacert
              pkgs.makeWrapper
              pkgs.which
            ];

            buildAttrs = {
              #preBuild = ''
              #  ${bazelForBuildBazelPackage}/bin/bazel info
              #  ${bazelForBuildBazelPackage}/bin/bazel build --host_platform=@bazel_tools//platforms:host_platform --platforms=@bazel_tools//platforms:host_platform --distdir=/build/output/external/cache --nofetch //java/dev/enola/cli:enola_deploy.jar
              #  exit 22
              #'';
              installPhase = ''
                mkdir -p "$out/share/java"
                #find $bazelOut
                cp $bazelOut/java/dev/enola/cli/enola_deploy.jar "$out/share/java"
                makeWrapper ${jdk'}/bin/java $out/bin/enola \
                  --add-flags "-jar $out/share/java/enola_deploy.jar"
              '';
            };
          };
        };

        apps = {
          test = {
            type = "app";
            program = "${
              pkgs.writeShellApplication {
                name = "test";
                runtimeInputs = buildTools;
                text = builtins.readFile ./test.bash;
              }
            }/bin/test";
          };
        };

        formatter = pkgs.nixfmt-tree;
      }
    );
}
