#!/usr/bin/env bash
# update-baseten.sh — Check for a new basetenlabs/baseten-cli release and
# update packages/baseten/sources.json (version + per-system tarball hashes).
#
# Usage: ./.github/scripts/update-baseten.sh
#
# Runs in CI and locally. It:
#   1. Reads the current version from packages/baseten/sources.json
#   2. Queries the latest release tag from the GitHub API (or VERSION_OVERRIDE)
#   3. Skips if no newer version is available
#   4. Prefetches each platform tarball with nix, cross-checking the hashes
#      against the checksums.txt published with the release
#   5. Rewrites sources.json
#   6. Exports metadata for the GitHub Actions workflow

set -euo pipefail

REPO="basetenlabs/baseten-cli"
SOURCES_JSON="packages/baseten/sources.json"

# nix system -> goreleaser archive name suffix (must match package.nix)
declare -A ASSETS=(
  [x86_64-linux]="linux_amd64"
  [aarch64-linux]="linux_arm64"
  [x86_64-darwin]="darwin_amd64"
  [aarch64-darwin]="darwin_arm64"
)

# ---------------------------------------------------------------------------
# Step 1: Current version
# ---------------------------------------------------------------------------

current_version="$(jq -r '.version' "${SOURCES_JSON}")"
echo "Current version in ${SOURCES_JSON}: ${current_version}"

# ---------------------------------------------------------------------------
# Step 2: Latest upstream version (or override)
# ---------------------------------------------------------------------------

if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  latest_version="${VERSION_OVERRIDE#v}"
  echo "Using overridden version: ${latest_version}"
else
  echo "Querying GitHub for the latest ${REPO} release..."
  curl_args=(-fsSL)
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  latest_tag="$(curl "${curl_args[@]}" "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')"

  if [[ -z "${latest_tag}" || "${latest_tag}" == "null" ]]; then
    echo "ERROR: Could not determine latest release tag." >&2
    exit 1
  fi
  latest_version="${latest_tag#v}"
fi

echo "Latest upstream version: ${latest_version}"

# ---------------------------------------------------------------------------
# Step 3: Skip if equal or older
# ---------------------------------------------------------------------------

if [[ "${current_version}" == "${latest_version}" ]]; then
  echo "Versions are equal. Nothing to do."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

newest="$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -n1)"
if [[ "${newest}" != "${latest_version}" ]]; then
  echo "Candidate version ${latest_version} is older than current ${current_version}. Skipping."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

VERSION="${latest_version}"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"

# ---------------------------------------------------------------------------
# Step 4: Fetch upstream checksums.txt for cross-verification
# ---------------------------------------------------------------------------

echo "Fetching upstream checksums.txt..."
checksums="$(curl -fsSL "${BASE_URL}/checksums.txt")"

expected_hex_for() {
  local archive="$1"
  grep -E "[[:space:]]${archive}\$" <<< "${checksums}" | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# Step 5: Prefetch tarballs, verify against checksums.txt, collect hashes
# ---------------------------------------------------------------------------

declare -A HASHES=()

for system in "${!ASSETS[@]}"; do
  archive="baseten_${VERSION}_${ASSETS[$system]}.tar.gz"
  url="${BASE_URL}/${archive}"
  echo "Prefetching ${archive}..."

  hash="$(nix store prefetch-file --json --hash-type sha256 "${url}" | jq -r '.hash')"

  if [[ -z "${hash}" || "${hash}" == "null" ]]; then
    echo "ERROR: Failed to prefetch ${url}" >&2
    exit 1
  fi

  # Cross-check against the checksums.txt published with the release.
  expected_hex="$(expected_hex_for "${archive}")"
  if [[ -z "${expected_hex}" ]]; then
    echo "ERROR: ${archive} not found in upstream checksums.txt" >&2
    exit 1
  fi
  actual_hex="$(nix hash convert --hash-algo sha256 --to base16 "${hash}")"
  if [[ "${actual_hex}" != "${expected_hex}" ]]; then
    echo "ERROR: hash mismatch for ${archive}" >&2
    echo "  prefetched: ${actual_hex}" >&2
    echo "  checksums.txt: ${expected_hex}" >&2
    exit 1
  fi

  HASHES[$system]="${hash}"
  echo "  ${system}: ${hash} (verified against checksums.txt)"
done

# ---------------------------------------------------------------------------
# Step 6: Rewrite sources.json
# ---------------------------------------------------------------------------

jq -n \
  --arg version "${VERSION}" \
  --arg x86_64_linux "${HASHES[x86_64-linux]}" \
  --arg aarch64_linux "${HASHES[aarch64-linux]}" \
  --arg x86_64_darwin "${HASHES[x86_64-darwin]}" \
  --arg aarch64_darwin "${HASHES[aarch64-darwin]}" \
  '{
    version: $version,
    hashes: {
      "x86_64-linux": $x86_64_linux,
      "aarch64-linux": $aarch64_linux,
      "x86_64-darwin": $x86_64_darwin,
      "aarch64-darwin": $aarch64_darwin
    }
  }' > "${SOURCES_JSON}.tmp"
mv "${SOURCES_JSON}.tmp" "${SOURCES_JSON}"

git add "${SOURCES_JSON}" 2>/dev/null || true
echo "Updated ${SOURCES_JSON}: ${current_version} -> ${VERSION}"

# ---------------------------------------------------------------------------
# Step 7: Export metadata for GitHub Actions
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "UPDATE_REQUIRED=true" >> "${GITHUB_ENV}"
  echo "NEW_VERSION=${VERSION}" >> "${GITHUB_ENV}"
fi

echo "Update complete: ${current_version} -> ${VERSION}"
