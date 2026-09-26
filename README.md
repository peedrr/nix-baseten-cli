# nix-baseten-cli

A Nix flake packaging the [Baseten CLI](https://github.com/basetenlabs/baseten-cli)
from its official prebuilt release binaries (statically linked Go, `CGO_ENABLED=0`).

Supported systems: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.

## Usage

### Try it without installing

```bash
nix run github:peedrr/nix-baseten-cli
```

### Install into your profile

```bash
nix profile install github:peedrr/nix-baseten-cli
```

### NixOS

```nix
{
  inputs.baseten.url = "github:peedrr/nix-baseten-cli";

  outputs = { nixpkgs, baseten, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      modules = [
        baseten.nixosModules.default
        { programs.baseten.enable = true; }
      ];
    };
  };
}
```

### home-manager

```nix
{
  inputs.baseten.url = "github:peedrr/nix-baseten-cli";

  # inside your home-manager configuration modules:
  imports = [ inputs.baseten.homeModules.default ];
  programs.baseten.enable = true;
}
```

### Overlay

```nix
nixpkgs.overlays = [ inputs.baseten.overlays.default ];
# then: environment.systemPackages = [ pkgs.baseten ];
```

## Automatic updates

`.github/workflows/update-baseten.yml` runs hourly and:

1. Checks `basetenlabs/baseten-cli` for a newer release.
2. Prefetches every platform tarball with Nix and **cross-verifies the hashes
   against the `checksums.txt` published with the release**.
3. Updates `packages/baseten/sources.json`, refreshes `flake.lock` when it is
   older than 7 days, builds the package, and smoke-tests `baseten --version`.
4. Opens a PR from `automation/update-baseten` and merges it with
   `--squash --admin`.

You can also trigger it manually with an optional version override:

```bash
gh workflow run update-baseten.yml -f version=1.0.0
```

### Authentication

The workflow uses `secrets.BASETEN_UPDATER_TOKEN` if present, falling back to
the built-in `GITHUB_TOKEN`. A PAT is recommended because PRs created by
`GITHUB_TOKEN` do not trigger other workflows (e.g. CI on the update PR).
Create a fine-grained PAT with **contents** and **pull requests** write access
to this repository and add it as the `BASETEN_UPDATER_TOKEN` secret.

## Layout

```text
flake.nix                        packages, apps, overlay, nixos/home modules
packages/baseten/package.nix     binary package (reads sources.json)
packages/baseten/sources.json    version + per-system tarball hashes
.github/scripts/update-baseten.sh    release check + hash prefetch/verify
.github/workflows/update-baseten.yml hourly update + auto-merge
```
