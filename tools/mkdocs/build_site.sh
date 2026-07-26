#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="./tools/mkdocs"

# Usage : ./build_site.sh <joueur|mj|monstres|portal>  <fr|en|root>
SITE="${1:?Usage: $0 <joueur|mj|monstres|portal> <fr|en|root>}"
LANG_CODE="${2:?Usage: $0 <joueur|mj|monstres|portal> <fr|en|root>}"

# path par combinaison site x langue
declare -A SITE_NAMES=(
  [joueur_fr]="manuel-du-joueu"
  [joueur_en]="player-handbook"
  [mj_fr]="supplement-du-mj"
  [mj_en]="DM-supplies"
  [monstres_fr]="manuel-des-monstres"
  [monstres_en]="monster-manual"
)

case "$SITE" in
  full) SITE_TITLE="Full" ;;
  joueur) SITE_TITLE="Manuel du Joueur" ;;
  mj) SITE_TITLE="Manuel du MJ" ;;
  monstres) SITE_TITLE="Manuel des monstres" ;;
  portal) SITE_TITLE="Portail" ;;
  *)
    echo "Site inconnu : '$SITE' (attendu : joueur, mj, monstres, portal)" >&2
    exit 1
    ;;
esac

case "$LANG_CODE" in
  fr|en) ;;
  root)
    if [ "$SITE" != "portal" ]; then
      echo "La langue 'root' n'est valable que pour le site 'portal'" >&2
      exit 1
    fi
    ;;
  *)
    echo "Langue inconnue : '$LANG_CODE' (attendu : fr, en, root)" >&2
    exit 1
    ;;
esac

SITE_NAME="${SITE_NAMES[${SITE}_${LANG_CODE}]:-}"
if [ -z "$SITE_NAME" ] ; then
  echo "Combinaison inconnue : site='$SITE' langue='$LANG_CODE'" >&2
  exit 1
fi

CONFIG_FILE="$BASE_DIR/mkdocs-${SITE}-${LANG_CODE}.yml"

# Set timer
debut=$(date +%s)

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Fichier de config introuvable : $CONFIG_FILE" >&2
  exit 1
fi

echo "Build de '$SITE_TITLE' [$LANG_CODE] avec $CONFIG_FILE ..."
mkdocs build --config-file "$CONFIG_FILE"

# Copie des assets partagés (CSS, etc.) non gérés par mkdocs car hors docs_dir.
# On les copie directement dans site_dir, après le build, plutôt que de dupliquer
# des symlinks dans chaque docs_dir.

SHARED_STYLESHEETS_DIR="./tools/mkdocs/stylesheets"
SITE_DIR=site/$LANG_CODE/$SITE_NAME
echo $SITE_DIR

if [ -d "$SHARED_STYLESHEETS_DIR" ]; then
  mkdir -p "$SITE_DIR/stylesheets"
  cp -f "$SHARED_STYLESHEETS_DIR"/*.css "$SITE_DIR/stylesheets/"
else
  echo "Attention : dossier d'assets partagés introuvable : $SHARED_STYLESHEETS_DIR" >&2
fi

# Log fin opérations
fin=$(date +%s)
duree=$((fin - debut))

echo "Site '$SITE' ($SITE_TITLE) [$LANG_CODE] généré en $duree secondes"
