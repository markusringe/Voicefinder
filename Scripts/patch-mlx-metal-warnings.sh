#!/usr/bin/env bash
# Unterdrückt bekannte MLX-Metal-Warnungen (-Wc++17-extensions) in Xcode 26+.
# Siehe: https://github.com/ml-explore/mlx-swift/issues/342
set -euo pipefail

MARKER="voicefinder-mlx-metal-diagnostic-guard"
INCLUDE_LINE='#include "../../../steel/attn/kernels/steel_attention.h"'

find_checkout_root() {
  local hint="${1:-}"
  if [[ -n "$hint" && -d "$hint/SourcePackages/checkouts/mlx-swift" ]]; then
    echo "$hint/SourcePackages/checkouts/mlx-swift"
    return 0
  fi

  local derived_root="$HOME/Library/Developer/Xcode/DerivedData"
  local latest
  latest="$(find "$derived_root" -maxdepth 1 -type d -name 'Voicefinder-*' 2>/dev/null | sort | tail -1)"
  if [[ -n "$latest" && -d "$latest/SourcePackages/checkouts/mlx-swift" ]]; then
    echo "$latest/SourcePackages/checkouts/mlx-swift"
    return 0
  fi
  return 1
}

patch_metal_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 1
  fi
  if grep -q "$MARKER" "$file"; then
    return 0
  fi
  if ! grep -qF "$INCLUDE_LINE" "$file"; then
    echo "→ Unerwarteter Inhalt in $file – Patch übersprungen."
    return 2
  fi

  chmod u+w "$file"

  local tmp
  tmp="$(mktemp)"
  awk -v marker="$MARKER" -v include="$INCLUDE_LINE" '
    $0 ~ include && !patched {
      print "// " marker
      print "#pragma clang diagnostic push"
      print "#pragma clang diagnostic ignored \"-Wc++17-extensions\""
      print "#pragma clang diagnostic ignored \"-Wc++20-extensions\""
      print ""
      print $0
      print ""
      print "#pragma clang diagnostic pop"
      patched = 1
      next
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
  echo "→ MLX-Metal gepatcht: $file"
}

main() {
  local derived_hint="${1:-${BUILD_DIR%/Build/*:-}}"
  local checkout
  if ! checkout="$(find_checkout_root "$derived_hint")"; then
    echo "→ MLX-Checkout nicht gefunden – Patch übersprungen."
    exit 0
  fi

  local metal_file="$checkout/Source/Cmlx/mlx-generated/metal/steel/attn/kernels/steel_attention.metal"
  if patch_metal_file "$metal_file"; then
    echo "✓ MLX-Metal-Warnungen unterdrückt."
  else
    echo "→ steel_attention.metal nicht gefunden."
    exit 0
  fi
}

main "$@"
