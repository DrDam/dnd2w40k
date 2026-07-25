#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="./tools/mkdocs"

# Usage : ./build_site.sh <joueur|mj|monstres>  <fr|en>
SITE="${1:?Usage: $0 <joueur|mj|monstres|full>}"
LANG_CODE="${2:?Usage: $0 <joueur|mj|monstres|full> <fr|en>}"

case "$SITE" in
  full) SITE_TITLE="Full" ;;
  joueur) SITE_TITLE="Manuel du Joueur" ;;
  mj) SITE_TITLE="Manuel du MJ" ;;
  monstres) SITE_TITLE="Manuel des monstres" ;;
  *)
    echo "Site inconnu : '$SITE' (attendu : joueur, mj, monstres)" >&2
    exit 1
    ;;
esac

case "$LANG_CODE" in
  fr|en) ;;
  *)
    echo "Langue inconnue : '$LANG_CODE' (attendu : fr, en)" >&2
    exit 1
    ;;
esac

CONFIG_FILE="$BASE_DIR/mkdocs-${SITE}-${LANG_CODE}.yml"

# Set timer
debut=$(date +%s)

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Fichier de config introuvable : $CONFIG_FILE" >&2
  exit 1
fi

echo "Build de '$SITE_TITLE' [$LANG_CODE] avec $CONFIG_FILE ..."
mkdocs build --config-file "$CONFIG_FILE"

# Log fin opérations
fin=$(date +%s)
duree=$((fin - debut))

echo "Site '$SITE' ($SITE_TITLE) [$LANG_CODE] généré en $duree secondes"
