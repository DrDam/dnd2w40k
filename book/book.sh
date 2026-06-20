#/bin/bash

pandoc \
  $(cat book/order.txt) \
  -o build/dnd-rules.pdf \
  --number-sections \
  --pdf-engine=xelatex \
  --metadata-file=book/metadata.yaml \
  --include-before-body=book/titlepage.tex \
  --resource-path=docs/assets \
  -f markdown-implicit_figures
