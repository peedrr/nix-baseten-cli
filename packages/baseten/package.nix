{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  sources = lib.importJSON ./sources.json;

  system = stdenvNoCC.hostPlatform.system;

  # nix system -> goreleaser archive name suffix
  assets = {
    x86_64-linux = "linux_amd64";
    aarch64-linux = "linux_arm64";
    x86_64-darwin = "darwin_amd64";
    aarch64-darwin = "darwin_arm64";
  };

  asset =
    assets.${system}
      or (throw "baseten: unsupported system '${system}' (supported: ${builtins.concatStringsSep ", " (builtins.attrNames assets)})");
in
stdenvNoCC.mkDerivation {
  pname = "baseten";
  version = sources.version;

  src = fetchurl {
    url = "https://github.com/basetenlabs/baseten-cli/releases/download/v${sources.version}/baseten_${sources.version}_${asset}.tar.gz";
    hash = sources.hashes.${system};
  };

  # The release tarball has no top-level directory.
  sourceRoot = ".";

  # Statically linked (upstream builds with CGO_ENABLED=0), already stripped.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 baseten $out/bin/baseten
    install -Dm644 LICENSE $out/share/licenses/baseten/LICENSE
    install -Dm644 README.md $out/share/doc/baseten/README.md

    runHook postInstall
  '';

  meta = {
    description = "CLI for Baseten — build, deploy, and manage ML model deployments";
    homepage = "https://github.com/basetenlabs/baseten-cli";
    changelog = "https://github.com/basetenlabs/baseten-cli/releases/tag/v${sources.version}";
    license = lib.licenses.mit;
    platforms = builtins.attrNames assets;
    mainProgram = "baseten";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
