{
  description = "code-on-incus (coi) — sandboxed AI coding agent sessions in Incus containers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Incus is Linux-only, so coi is too.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = final: prev: {
        code-on-incus = self.packages.${final.stdenv.hostPlatform.system}.code-on-incus;
      };

      packages = forAllSystems (pkgs: rec {
        default = code-on-incus;

        code-on-incus = pkgs.buildGoModule (finalAttrs: {
          pname = "code-on-incus";
          version = "0.9.0";

          src = pkgs.fetchFromGitHub {
            owner = "mensfeld";
            repo = "code-on-incus";
            rev = "v${finalAttrs.version}";
            hash = "sha256-jMVOWiyp1zoMsp5zB8KClksRXJ1LYbye7g+j+PW1RSI=";
          };

          vendorHash = "sha256-Mij7aw4jd5aQsJWpaUc5tk8ZK/X3bojmoxLnjdIohBI=";

          subPackages = [ "cmd/coi" ];

          # cgo: reads the systemd journal for NFT monitoring (libsystemd).
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.systemd ];

          ldflags = [
            "-s"
            "-w"
            "-X github.com/mensfeld/code-on-incus/internal/cli.Version=${finalAttrs.version}"
          ];

          # Mirror the Makefile's `build` target: stage files that the Go
          # sources pull in via go:embed before compiling.
          preBuild = ''
            mkdir -p internal/image/embedded internal/config/embedded
            cp profiles/default/build.sh internal/image/embedded/coi_build.sh
            cp profiles/default/config.toml internal/config/embedded/default_config.toml
            cp testdata/dummy/dummy internal/image/embedded/dummy
          '';

          # Unit tests only (the Makefile's `make test` equivalent); integration
          # tests need a running Incus daemon.
          checkFlags = [ "-short" ];

          meta = {
            description = "Run AI coding agents (Claude Code, Codex, ...) in isolated Incus containers";
            homepage = "https://github.com/mensfeld/code-on-incus";
            changelog = "https://github.com/mensfeld/code-on-incus/blob/v${finalAttrs.version}/CHANGELOG.md";
            license = pkgs.lib.licenses.mit;
            mainProgram = "coi";
            platforms = systems;
          };
        });
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = [ self.packages.${pkgs.stdenv.hostPlatform.system}.code-on-incus ];
          packages = with pkgs; [
            go
            gopls
            incus
          ];
        };
      });
    };
}
