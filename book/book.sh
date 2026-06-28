#!/usr/bin/env bash

set -euo pipefail

# Set timer
debut=$(date +%s)

# Build du PDF : préprocessing des admonitions MkDocs -> fenced divs,

BUILD_DIR="build"
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
  python3 book/macro/admonition_to_div.py "$src_file" \
    | python3 book/macro/resolve_image_paths.py "$src_file" \
    > "$dest_file"
  PREPROCESSED_FILES+=("$dest_file")
}

PREPROCESSED_FILES=()
while IFS= read -r entry; do
  # Ignore les lignes vides éventuelles dans order.txt
  [ -z "$entry" ] && continue

  # Retire un éventuel suffixe "/*.md" pour ne garder que le chemin du dossier
  dir_candidate="${entry%/\*.md}"

  if [ -d "$dir_candidate" ]; then
    # C'est un dossier : on prend tous les .md, triés alphabétiquement
    # C entraîne un tri en ordre ASCII strict (indépendant de la locale système)
    while IFS= read -r -d '' md_file; do
      preprocess_one "$md_file"
    done < <(find "$dir_candidate" -maxdepth 1 -name '*.md' -print0 | LC_COLLATE=C sort -z)
  else
    # Fichier .md unique
    preprocess_one "$entry"
  fi
done < book/order.txt

# puis génération Pandoc.

pandoc \
  "${PREPROCESSED_FILES[@]}" \
  -o "$BUILD_DIR/dnd-rules.pdf" \
  --number-sections \
  --top-level-division=part \
  --pdf-engine=xelatex \
  --metadata-file=book/metadata.yaml \
  --include-before-body=book/titlepage.tex \
  --resource-path=docs/assets \
  --lua-filter=book/macro/admonition.lua \
  --lua-filter=book/macro/statblock.lua \
  --lua-filter=book/macro/tables.lua \
  --lua-filter=book/macro/newpage.lua \
  --lua-filter=book/macro/wide_image.lua \
  --lua-filter=book/macro/part_cover.lua \
  -H book/preamble.tex \
  -f markdown-implicit_figures

# Log fin opérations
fin=$(date +%s)
duree=$((fin - debut))

echo "PDF généré en $duree secondes"
