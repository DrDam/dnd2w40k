#!/usr/bin/env bash

set -euo pipefail

BASE_DIR="tools/book"

# Usage : ./book.sh <joueur|mj|monstres> <fr|en>
LIVRE="${1:?Usage: $0 <joueur|mj|monstres> <fr|en>}"
LANG_CODE="${2:?Usage: $0 <joueur|mj|monstres> <fr|en>}"

case "$LIVRE" in
  joueur|mj|monstres) ;;
  *)
    echo "Livre inconnu : '$LIVRE' (attendu : joueur, mj, monstres)" >&2
    exit 1
    ;;
esac

# Titres par combinaison livre x langue
declare -A BOOKTITLES=(
  [joueur_fr]="Manuel du Joueur"
  [joueur_en]="Player's Handbook"
  [mj_fr]="Manuel du Maître du Jeu"
  [mj_en]="Game Master's Guide"
  [monstres_fr]="Manuel des Monstres"
  [monstres_en]="Monster Manual"
)

# Noms de fichiers de sortie par combinaison livre x langue
# (le nom de sortie peut différer du simple "titre-lang", ex. traduction du titre)
declare -A OUT_NAMES=(
  [joueur_fr]="manuel-du-joueur"
  [joueur_en]="players-handbook"
  [mj_fr]="manuel-du-mj"
  [mj_en]="game-masters-guide"
  [monstres_fr]="manuel-des-monstres"
  [monstres_en]="monster-manual"
)

BOOKTITLE="${BOOKTITLES[${LIVRE}_${LANG_CODE}]:-}"
OUT="${OUT_NAMES[${LIVRE}_${LANG_CODE}]:-}"
if [ -z "$BOOKTITLE" ] || [ -z "$OUT" ]; then
  echo "Combinaison inconnue : livre='$LIVRE' langue='$LANG_CODE' (attendu : fr, en)" >&2
  exit 1
fi

ORDER_FILE="$BASE_DIR/order-${LIVRE}-${LANG_CODE}.txt"

# Fichier de métadonnées Pandoc par langue (typographie, césure, libellés LaTeX...)
METADATA_FILE="$BASE_DIR/metadata-${LANG_CODE}.yaml"
if [ ! -f "$METADATA_FILE" ]; then
  echo "Fichier de métadonnées introuvable : $METADATA_FILE" >&2
  exit 1
fi

# Page de titre par langue
TITLEPAGE_FILE="$BASE_DIR/titlepage-${LANG_CODE}.tex"
if [ ! -f "$TITLEPAGE_FILE" ]; then
  echo "Fichier de page de titre introuvable : $TITLEPAGE_FILE" >&2
  exit 1
fi

# Set timer
debut=$(date +%s)

# Build du PDF : préprocessing des admonitions MkDocs -> fenced divs,

BUILD_DIR="build/${LIVRE}-${LANG_CODE}"
PREPROCESSED_DIR="$BUILD_DIR/preprocessed"

mkdir -p "$PREPROCESSED_DIR"

# Préprocesse chaque fichier listé dans order.txt, en conservant l'arborescence
# Une ligne de order.txt peut être :
#   - un fichier .md unique             -> docs/fr/foo/bar.md
#   - un dossier entier (trié par ordre alphabétique des fichiers .md)
#                                        -> docs/fr/foo/Dossier
#                                        -> docs/fr/foo/Dossier/*.md
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

# Dossier de sortie des PDF, classé par langue
OUT_DIR="./build/$LANG_CODE"
mkdir -p "$OUT_DIR"

pandoc \
  "${PREPROCESSED_FILES[@]}" \
  -o "./build/$OUT.pdf" \
  --number-sections \
  --top-level-division=part \
  --pdf-engine=xelatex \
  --columns=1 \
  --metadata-file="$METADATA_FILE" \
  --include-before-body="$TITLEPAGE_FILE" \
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

echo "PDF '$OUT' [$LANG_CODE] généré en $duree secondes -> $OUT_DIR/$OUT.pdf"
