#!/usr/bin/env bash

set -euo pipefail

# Build du PDF : préprocessing des admonitions MkDocs -> fenced divs,

BUILD_DIR="build"
PREPROCESSED_DIR="$BUILD_DIR/preprocessed"

mkdir -p "$PREPROCESSED_DIR"

# Préprocesse chaque fichier listé dans order.txt, en conservant l'arborescence
PREPROCESSED_FILES=()
while IFS= read -r src_file; do
  # Ignore les lignes vides éventuelles dans order.txt
  [ -z "$src_file" ] && continue

  dest_file="$PREPROCESSED_DIR/$src_file"
  mkdir -p "$(dirname "$dest_file")"
  python3 book/macro/admonition_to_div.py "$src_file" > "$dest_file"
  PREPROCESSED_FILES+=("$dest_file")
done < book/order.txt

# puis génération Pandoc.

pandoc \
  "${PREPROCESSED_FILES[@]}" \
  -o "$BUILD_DIR/dnd-rules.pdf" \
  --number-sections \
  --pdf-engine=xelatex \
  --metadata-file=book/metadata.yaml \
  --include-before-body=book/titlepage.tex \
  --resource-path=docs/assets \
  --lua-filter=book/macro/admonition.lua \
  -H book/preamble.tex \
  -f markdown-implicit_figures

echo "PDF généré : $BUILD_DIR/dnd-rules.pdf"
