#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="tools/book"

# Usage : ./book.sh <joueur|mj|monstres>
LIVRE="${1:?Usage: $0 <joueur|mj|monstres>}"

case "$LIVRE" in
  joueur)
    ORDER_FILE="$BASE_DIR/order-joueur.txt"
    BOOKTITLE="Manuel du Joueur"
    OUT="manuel-du-joueur"
    ;;
  mj)
    ORDER_FILE="$BASE_DIR/order-mj.txt"
    BOOKTITLE="Manuel du Maître du Jeu"
    OUT="manuel-du-mj"
    ;;
  monstres)
    ORDER_FILE="$BASE_DIR/order-monstres.txt"
    BOOKTITLE="Manuel des Monstres"
    OUT="manuel-des-monstres"
    ;;
  *)
    echo "Livre inconnu : '$LIVRE' (attendu : joueur, mj, monstres)" >&2
    exit 1
    ;;
esac

# Set timer
debut=$(date +%s)

# Build du PDF : préprocessing des admonitions MkDocs -> fenced divs,

BUILD_DIR="build/$LIVRE"
PREPROCESSED_DIR="$BUILD_DIR/preprocessed"

mkdir -p "$PREPROCESSED_DIR"

# Préprocesse chaque fichier listé dans order.txt, en conservant l'arborescence
# Une ligne de order.txt peut être :
#   - un fichier .md unique             -> docs/foo/bar.md
#   - un dossier entier (trié par ordre alphabétique des fichiers .md)
#                                        -> docs/foo/Dossier
#                                        -> docs/foo/Dossier/*.md
preprocess_one() {
  local src_file="$1"
  local dest_file="$PREPROCESSED_DIR/$src_file"
  mkdir -p "$(dirname "$dest_file")"
  python3 $BASE_DIR/macro/admonition_to_div.py "$src_file" \
    | python3 $BASE_DIR/macro/multicol_markers.py \
    | python3 $BASE_DIR/macro/resolve_image_paths.py "$src_file" \
    | python3 $BASE_DIR/macro/resolve_internal_links.py \
    |  BUILD_DIR="$BUILD_DIR" python3 $BASE_DIR/macro/optimize_images.py \
    > "$dest_file"
  PREPROCESSED_FILES+=("$dest_file")
}

if [ ! -f "$ORDER_FILE" ]; then
  echo "Fichier d'ordre introuvable : $ORDER_FILE" >&2
  exit 1
fi

PREPROCESSED_FILES=()
while IFS= read -r entry; do
  # Ignore les lignes vides éventuelles dans order.txt
  [ -z "$entry" ] && continue

  # Retire un éventuel suffixe "/*.md" pour ne garder que le chemin du dossier
  dir_candidate="${entry%/\*.md}"

  if [ -d "$dir_candidate" ]; then
    # C'est un dossier : on prend tous les .md, triés alphabétiquement
    # Le tri en LC_COLLATE=C entraîne un tri en ordre ASCII strict (indépendant de la locale système)
    while IFS= read -r -d '' md_file; do
      preprocess_one "$md_file"
    done < <(find "$dir_candidate" -maxdepth 1 -name '*.md' -print0 | LC_COLLATE=C sort -z)
  else
    # Fichier .md unique
    preprocess_one "$entry"
  fi
done < "$ORDER_FILE"

# puis génération Pandoc.

# Génère un petit fichier .tex définissant \BookSubtitle avec la bonne valeur
# pour ce livre. Nécessaire car les fichiers inclus via -H / --include-before-body
# ne sont PAS passés par le moteur de substitution de variables de Pandoc :
# une variable $subtitle$ y resterait littérale dans le PDF final.
SUBTITLE_DEF="$BUILD_DIR/subtitle-def.tex"
printf '\\newcommand{\\BookSubtitle}{%s}\n' "$BOOKTITLE" > "$SUBTITLE_DEF"

pandoc \
  "${PREPROCESSED_FILES[@]}" \
  -o "./build/$OUT.pdf" \
  --number-sections \
  --top-level-division=part \
  --pdf-engine=xelatex \
  --columns=1 \
  --metadata-file=$BASE_DIR/metadata.yaml \
  --include-before-body=$BASE_DIR/titlepage.tex \
  --resource-path=docs/assets \
  --lua-filter=$BASE_DIR/macro/admonition.lua \
  --lua-filter=$BASE_DIR/macro/multicol.lua \
  --lua-filter=$BASE_DIR/macro/statblock.lua \
  --lua-filter=$BASE_DIR/macro/tables.lua \
  --lua-filter=$BASE_DIR/macro/newpage.lua \
  --lua-filter=$BASE_DIR/macro/wide_image.lua \
  --lua-filter=$BASE_DIR/macro/part_cover.lua \
  -H "$SUBTITLE_DEF" \
  -H $BASE_DIR/preamble.tex \
  -f markdown-implicit_figures

# Log fin opérations
fin=$(date +%s)
duree=$((fin - debut))

# Clean directory
rm -rf $BUILD_DIR

echo "PDF '$OUT' généré en $duree secondes -> build/$OUT.pdf"
