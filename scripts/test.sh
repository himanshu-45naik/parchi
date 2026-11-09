#!/bin/bash
# Runs the core checks.
set -euo pipefail
cd "$(dirname "$0")/.."
exec swift run ParchiCoreCheck
