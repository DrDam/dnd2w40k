#!/usr/bin/env bash

set -uo pipefail
# Note : pas de -e ici, on veut pouvoir continuer même si un site échoue
# et faire le bilan à la fin.

SITES=(joueur mj monstres)
LANGS=(fr en)

debut_total=$(date +%s)

echec=()
reussite=()

for site in "${SITES[@]}"; do
  for lang in "${LANGS[@]}"; do
    echo "- Site $site [$lang] : Génération ..."

    if ./tools/mkdocs/build_site.sh "$site" "$lang"; then
      reussite+=("$site-$lang")
    else
      echo "ÉCHEC lors de la génération de : $site [$lang]" >&2
      echec+=("$site-$lang")
    fi
    echo
  done
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

echo "Tous les sites ont été générés avec succès."
