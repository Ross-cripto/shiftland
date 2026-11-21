#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
exec "$repository_root/macos/scripts/build-app.sh" "$@"
