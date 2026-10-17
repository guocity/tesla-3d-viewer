#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/create_app_bundle.sh"
open "$SCRIPT_DIR/TeslaMetalViewer.app" --args "$@"
