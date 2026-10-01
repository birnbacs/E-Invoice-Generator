#!/bin/zsh
# Lädt den Mustang-Validator (nur für die Entwicklung) und prüft, ob Java vorhanden ist.
set -e
cd "$(dirname "$0")/.."
VERSION=2.26.0
JAR="Tools/Mustang-CLI-$VERSION.jar"
mkdir -p Tools
if [[ ! -f "$JAR" ]]; then
  curl -fSL -o "$JAR" "https://repo1.maven.org/maven2/org/mustangproject/Mustang-CLI/$VERSION/Mustang-CLI-$VERSION.jar"
fi
[[ -x /opt/homebrew/opt/openjdk/bin/java ]] || brew install openjdk
echo "Werkzeuge bereit: $JAR"
