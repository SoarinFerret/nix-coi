# nix-coi

Nix flake packaging [code-on-incus](https://github.com/mensfeld/code-on-incus) (`coi`) —
a CLI for running AI coding agents (Claude Code, Codex, ...) in isolated Incus containers.

## Usage

Run directly:

```sh
nix run github:soarinferret/nix-coi   # or: nix run /path/to/this/repo
```

Build locally:

```sh
nix build .#code-on-incus
./result/bin/coi --version
```

Add to a NixOS / home-manager configuration via the overlay:

```nix
{
  inputs.nix-coi.url = "github:soarinferret/nix-coi";

  # then in your config:
  nixpkgs.overlays = [ inputs.nix-coi.overlays.default ];
  environment.systemPackages = [ pkgs.code-on-incus ];
}
```

## Runtime requirements

`coi` drives Incus on the host, so the machine needs a working Incus daemon and
your user in the `incus-admin` group. On NixOS:

```nix
virtualisation.incus.enable = true;
users.users.<you>.extraGroups = [ "incus-admin" ];
```

Some features additionally use host tools discovered at runtime: `nft`
(network filtering), `journalctl` (NFT monitoring), and `iptables`.

## Notes

- Pinned to the v0.9.0 release; bump `version` and the two hashes in
  `flake.nix` to update (set `vendorHash` to a dummy value and copy the
  hash from the build error).
- Built with cgo against libsystemd, mirroring the upstream Makefile,
  including the `go:embed` staging steps and version injection via ldflags.
- Unit tests run in the check phase (`-short`); integration tests are skipped
  since they need a live Incus daemon.
