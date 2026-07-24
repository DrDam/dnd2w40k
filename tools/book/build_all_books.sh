#!/usr/bin/env bash

set -uo pipefail
# Note : pas de -e ici, on veut pouvoir continuer même si un livre échoue
# et faire le bilan à la fin.

LIVRES=(joueur mj monstres)

debut_total=$(date +%s)

echec=()
reussite=()

for livre in "${LIVRES[@]}"; do
  echo "- Livre $livre : Génération ..."

  if ./tools/book/book.sh "$livre"; then
    reussite+=("$livre")
  else
    echo "ÉCHEC lors de la génération de : $livre" >&2
    echec+=("$livre")
  fi
  echo
done

fin_total=$(date +%s)
duree_total=$((fin_total - debut_total))

echo "= Bilan"
echo "Durée totale : ${duree_total}s"

if [ "${#reussite[@]}" -gt 0 ]; then
  echo "Réussis  : ${reussite[*]}"
fi

if [ "${#echec[@]}" -gt 0 ]; then
  echo "Échoués  : ${echec[*]}" >&2
  exit 1
fi

echo "Tous les livres ont été générés avec succès."
