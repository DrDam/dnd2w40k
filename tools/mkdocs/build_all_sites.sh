#!/usr/bin/env bash

set -uo pipefail
# Note : pas de -e ici, on veut pouvoir continuer même si un site échoue
# et faire le bilan à la fin.

SITES=(joueur mj monstres)
LANGS=(fr en)

debut_total=$(date +%s)

echec=()
reussite=()

build_one() {
  local site="$1" lang="$2"
  echo "- Site $site [$lang] : Génération ..."
  if ./tools/mkdocs/build_site.sh "$site" "$lang"; then
    reussite+=("$site-$lang")
  else
    echo "ÉCHEC lors de la génération de : $site [$lang]" >&2
    echec+=("$site-$lang")
  fi
  echo
}

# IMPORTANT : ordre de build.
# mkdocs nettoie (clean) son propre site_dir à chaque build.
# On construit donc du plus "englobant" au plus "spécifique" :
#   1) portail racine   -> site_dir = site/            (nettoie tout le site/)
#   2) portails fr / en  -> site_dir = site/fr, site/en  (nettoie leur sous-dossier)
#   3) livres fr / en    -> site_dir = site/fr/joueur, etc. (nettoie leur propre sous-dossier)
# Si on inversait l'ordre, un portail construit après les livres
# effacerait leurs pages en nettoyant son site_dir parent.

build_one portal root
build_one portal fr
build_one portal en

for site in "${SITES[@]}"; do
  for lang in "${LANGS[@]}"; do
    build_one "$site" "$lang"
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
fi
