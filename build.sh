#/bin/bash

echo "#################"
echo "# Build project #"
echo "#################"

echo ""
echo "** Generate PDF **"

./book/build_all_books.sh

echo ""
echo "** Generate MKdoc **"

mkdocs build
