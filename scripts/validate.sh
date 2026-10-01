#!/bin/zsh
# Prüft E-Rechnungen mit Mustang (PDF/A-3 + ZUGFeRD/EN 16931).
# Verwendung: scripts/validate.sh datei1.pdf [datei2.pdf ...]
set -e
cd "$(dirname "$0")/.."
JAR=$(ls Tools/Mustang-CLI-*.jar | tail -1)
JAVA=/opt/homebrew/opt/openjdk/bin/java
rc=0
for f in "$@"; do
  report=$("$JAVA" -jar "$JAR" --action validate --source "$f" --no-notices 2>/dev/null)
  if echo "$report" | tail -3 | grep -q 'status="valid"'; then
    echo "✓ gültig:   $f"
  else
    echo "✗ UNGÜLTIG: $f"
    echo "$report" | grep -E "<error|<warning|<exception" | sed 's/^ */    /'
    rc=1
  fi
done
exit $rc
