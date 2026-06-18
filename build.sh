#/bin/bash

echo "#################"
echo "# Build project #"
echo "#################"

echo ""
echo "** Generate PDF **"

./book/book.sh

echo ""
echo "** Generate MKdoc **"

mkdocs build
