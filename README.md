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

## NixOS module (recommended)

The flake ships a NixOS module that sets up everything coi needs on the host:

```nix
{
  inputs.nix-coi.url = "github:soarinferret/nix-coi";

  # then in your NixOS config:
  imports = [ inputs.nix-coi.nixosModules.default ];
  programs.code-on-incus.enable = true;
  users.users.<you>.extraGroups = [ "incus-admin" ];
}
```

Enabling it takes care of:

- installing `coi` (plus `git`, needed by `coi update patterns`)
- `virtualisation.incus.enable` (Incus daemon, idmap setup)
- trusting the Incus bridge in the firewall so containers get DHCP/DNS
  (`bridgeInterface`, default `incusbr0`)
- nftables + passwordless sudo for `nft` for the `incus-admin` group,
  required by coi's restricted/allowlist network modes
  (`networkIsolation.enable`, default on)
- a `CAP_LINUX_IMMUTABLE` capability wrapper for coi — the NixOS
  equivalent of upstream's `setcap` step, since store paths can't carry
  capabilities (`immutableWrapper.enable`, default on)

Not covered, by design: creating an Incus storage pool (upstream's installer
offers a 50 GiB ZFS pool — a stateful decision left to you) and fetching the
detection databases (run `coi update patterns` once after install).

## Plain package / overlay

```nix
nixpkgs.overlays = [ inputs.nix-coi.overlays.default ];
environment.systemPackages = [ pkgs.code-on-incus ];
```

With the plain package you must arrange Incus, the firewall exception for the
bridge, and the nft sudoers rule yourself. Runtime host tools coi looks for:
`incus`, `nft` (network filtering), `journalctl` (NFT monitoring), `iptables`,
and `aws` (only for the Bedrock backend).

## Notes

- Pinned to the v0.9.0 release; bump `version` and the two hashes in
  `flake.nix` to update (set `vendorHash` to a dummy value and copy the
  hash from the build error).
- Built with cgo against libsystemd, mirroring the upstream Makefile,
  including the `go:embed` staging steps and version injection via ldflags.
- Unit tests run in the check phase (`-short`); integration tests are skipped
  since they need a live Incus daemon.
