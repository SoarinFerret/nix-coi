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

      nixosModules.default = self.nixosModules.code-on-incus;
      nixosModules.code-on-incus =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.programs.code-on-incus;
        in
        {
          options.programs.code-on-incus = {
            enable = lib.mkEnableOption "code-on-incus (coi), sandboxed AI coding agent sessions in Incus containers";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.code-on-incus;
              defaultText = lib.literalExpression "code-on-incus from this flake";
              description = "The coi package to use.";
            };

            bridgeInterface = lib.mkOption {
              type = lib.types.str;
              default = "incusbr0";
              description = ''
                Incus bridge to add to the firewall's trusted interfaces so
                containers can reach the host's dnsmasq for DHCP and DNS.
              '';
            };

            networkIsolation = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = true;
                description = ''
                  Enable nftables and grant passwordless sudo for nft, which coi
                  needs for its restricted and allowlist network modes. Without
                  this only open mode works.
                '';
              };

              group = lib.mkOption {
                type = lib.types.str;
                default = "incus-admin";
                description = "Group granted passwordless sudo for nft.";
              };
            };

            immutableWrapper.enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = ''
                Install coi as a capability wrapper with CAP_LINUX_IMMUTABLE so
                it can chattr +i host-side protected paths (the NixOS equivalent
                of upstream's setcap step; store paths cannot be setcap'd).
              '';
            };
          };

          config = lib.mkIf cfg.enable (lib.mkMerge [
            {
              # git is needed by `coi update patterns` (clones GTFOBins/Sigma)
              environment.systemPackages = [
                cfg.package
                pkgs.git
              ];
              virtualisation.incus.enable = true;
              networking.firewall.trustedInterfaces = [ cfg.bridgeInterface ];
            }

            (lib.mkIf cfg.networkIsolation.enable {
              networking.nftables.enable = lib.mkDefault true;
              # coi runs `sudo -n nft ...`; sudo resolves the bare name through
              # secure_path, so the rule must match the system-path nft, not the
              # store path.
              security.sudo.extraRules = [
                {
                  groups = [ cfg.networkIsolation.group ];
                  commands = [
                    {
                      command = "/run/current-system/sw/bin/nft";
                      options = [ "NOPASSWD" ];
                    }
                  ];
                }
              ];
            })

            (lib.mkIf cfg.immutableWrapper.enable {
              # /run/wrappers/bin precedes the system path, so `coi` resolves to
              # the wrapper and the plain store binary stays available as a
              # fallback via the package.
              security.wrappers.coi = {
                source = lib.getExe cfg.package;
                owner = "root";
                group = "root";
                capabilities = "cap_linux_immutable=ep";
              };
            })
          ]);
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
