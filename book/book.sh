#/bin/bash

pandoc \
  $(cat book/order.txt) \
  -o build/dnd-rules.pdf \
  --toc \
  --number-sections \
  --pdf-engine=xelatex \
  --metadata-file=book/metadata.yaml
