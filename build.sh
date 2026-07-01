#/bin/bash

echo "###########################"
echo "# Production PDF / Mkdocs #"
echo "###########################"
echo ""

echo "==========================="
echo "==   Génération des PDF  =="
echo "==========================="
echo ""

./book/build_all_books.sh

echo ""
echo "==========================="
echo "==  Génération du MKdoc  =="
echo "==========================="
echo ""

mkdocs build

echo ""
echo "###########################"
echo "#           Fin           #"
echo "###########################"
