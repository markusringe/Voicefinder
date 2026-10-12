#!/usr/bin/env bash
# Setzt defekte Swift-Package-Caches zurück und löst Abhängigkeiten neu auf.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
SWIFT_PM_CACHE="$HOME/Library/Caches/org.swift.swiftpm/repositories"

echo "→ Voicefinder Swift-Package-Reset"
echo "→ Projekt: $ROOT"

# Nur Voicefinder-DerivedData entfernen.
find "$DERIVED_ROOT" -maxdepth 1 -name 'Voicefinder-*' -print0 2>/dev/null \
  | while IFS= read -r -d '' dir; do
      echo "→ Entferne $dir"
      rm -rf "$dir" || true
    done

# Häufig korrupte Checkouts aus globalem SPM-Cache löschen.
for repo in swift-nio swift-transformers; do
  rm -rf "$SWIFT_PM_CACHE/${repo}-"* 2>/dev/null || true
done

cd "$ROOT"

echo "→ Pakete auflösen …"
xcodebuild -resolvePackageDependencies -scheme Voicefinder

echo "→ MLX-Metal-Warnungen patchen (Xcode 26) …"
"${ROOT}/Scripts/patch-mlx-metal-warnings.sh"

echo ""
echo "✓ Fertig."
echo "  1. Xcode komplett schließen und Projekt neu öffnen"
echo "  2. Falls nötig: File → Packages → Reset Package Caches"
echo "  3. Product → Clean Build Folder (⇧⌘K), dann bauen"
