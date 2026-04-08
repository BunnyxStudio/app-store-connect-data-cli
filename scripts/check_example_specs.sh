#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

ADC_BIN="${ADC_BIN:-${REPO_ROOT}/.build/debug/adc}"
if [[ ! -x "${ADC_BIN}" ]]; then
  ADC_BIN="$(swift build --show-bin-path)/adc"
fi

for spec in examples/queries/*.json; do
  echo "Checking ${spec}"
  "${ADC_BIN}" query run --spec "${spec}" --offline --output json >/dev/null
done

echo "All example specs passed."
