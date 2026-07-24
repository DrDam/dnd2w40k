#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="./tools/mkdocs"

# Usage : ./build_site.sh <joueur|mj|monstres>
SITE="${1:?Usage: $0 <joueur|mj|monstres|full>}"

case "$SITE" in
  full)
    CONFIG_FILE="$BASE_DIR/mkdocs-full.yml"
    SITE_TITLE="Full"
    ;;
  joueur)
    CONFIG_FILE="$BASE_DIR/mkdocs-joueur.yml"
    SITE_TITLE="Manuel du Joueur"
    ;;
  mj)
    CONFIG_FILE="$BASE_DIR/mkdocs-mj.yml"
    SITE_TITLE="Manuel du MJ"
    ;;
  monstres)
    CONFIG_FILE="$BASE_DIR/mkdocs-monstres.yml"
    SITE_TITLE="Manuel des monstres"
    ;;
  *)
    echo "Site inconnu : '$SITE' (attendu : joueur, mj, monstres)" >&2
    exit 1
    ;;
esac



# Set timer
debut=$(date +%s)

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Fichier de config introuvable : $CONFIG_FILE" >&2
  exit 1
fi

echo "Build de '$SITE_TITLE' avec $CONFIG_FILE ..."
mkdocs build --config-file "$CONFIG_FILE"

# Log fin opérations
fin=$(date +%s)
duree=$((fin - debut))

echo "Site '$SITE' ($SITE_TITLE) généré en $duree secondes"
