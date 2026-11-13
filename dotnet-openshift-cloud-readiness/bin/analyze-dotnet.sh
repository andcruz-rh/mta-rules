#!/usr/bin/env bash
# Analyze a .NET / .NET Core app with this custom ruleset using MTA 8.x CLI.
# MTA 8.0 has no first-class .NET provider for these filecontent rules — we force
# --provider java so the builtin provider still evaluates patterns against
# .cs / .csproj / appsettings / web.config sources.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RULES="${PKG_DIR}/rules"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") --input <dotnet-app-path> --output <report-dir> [extra mta-cli flags...]

Examples:
  $(basename "$0") --input "${PKG_DIR}/fixture" --output /tmp/mta-dotnet-fixture
  $(basename "$0") --input /path/to/my-dotnet-app --output /tmp/mta-myapp

Requires: mta-cli on PATH (tested with 8.0.0).
EOF
}

INPUT=""
OUTPUT=""
EXTRA=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -i|--input) INPUT="${2:-}"; shift 2 ;;
    -o|--output) OUTPUT="${2:-}"; shift 2 ;;
    *) EXTRA+=("$1"); shift ;;
  esac
done

if [[ -z "${INPUT}" || -z "${OUTPUT}" ]]; then
  usage
  exit 1
fi

if ! command -v mta-cli >/dev/null 2>&1; then
  echo "ERROR: mta-cli not found in PATH" >&2
  exit 1
fi

if [[ ! -d "${RULES}" ]]; then
  echo "ERROR: rules directory not found: ${RULES}" >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

echo "mta-cli: $(command -v mta-cli)"
mta-cli version || true
echo "input:  ${INPUT}"
echo "output: ${OUTPUT}"
echo "rules:  ${RULES}"

# Critical for .NET source scans on MTA 8.x:
# - --provider java     avoids unsupported-language provider errors
# - --run-local=true    containerless; builtin still scans sources
# - --enable-default-rulesets=false  keep report focused on this ruleset
exec mta-cli analyze \
  --input "${INPUT}" \
  --output "${OUTPUT}" \
  --mode source-only \
  --provider java \
  --run-local=true \
  --rules "${RULES}" \
  --enable-default-rulesets=false \
  --label-selector "(konveyor.io/source=dotnet)" \
  --overwrite \
  "${EXTRA[@]}"
