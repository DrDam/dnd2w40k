#/bin/bash

echo "#################"
echo "# Build project #"
echo "#################"

echo ""
echo "** Generate PDF **"

pandoc \
  $(cat book/order.txt) \
  -o build/dnd-rules.pdf \
  --toc \
  --number-sections \
  --pdf-engine=xelatex \
  --metadata-file=book/metadata.yaml -v

echo ""
echo "** Generate MKdoc **"

mkdocs build
