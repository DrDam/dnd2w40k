#!/usr/bin/env python3
"""
Réécrit les liens internes Markdown au format MkDocs
(ex: [texte](autre_fichier.md#ancre)) en liens internes Pandoc
(ex: [texte](#ancre)), pour le build PDF.

Pourquoi : dans une arborescence MkDocs, chaque page est un document
HTML séparé -- un lien croisé DOIT donc préciser le fichier cible
(fichier.md#ancre) pour que MkDocs sache résoudre l'URL relative vers
l'autre page. Mais book-test.sh concatène tous les fichiers .md en UN
SEUL document avant de le passer à Pandoc : dans ce contexte, toutes
les ancres (#titre-1, #titre-2, ...) vivent dans le MÊME espace de
noms, et un lien qui garde le préfixe "fichier.md" ne correspond à
rien pour Pandoc/LaTeX (qui ignore silencieusement le lien ou le
casse). Il faut donc retirer le nom de fichier pour ne garder que
l'ancre.

Ne touche que les liens Markdown classiques [texte](cible), jamais les
images ![alt](cible) (regex avec lookbehind négatif "(?<!!)", même
principe que resolve_image_paths.py pour les images).

Ne réécrit QUE les cibles de la forme "quelquechose.md#ancre" (avec ou
sans chemin relatif devant, ex: ../foo/bar.md#ancre). Laisse intacts :
- les liens externes (http://, https://, mailto:)
- les liens vers un fichier SANS ancre (ex: [texte](autre.md)) : ce
  cas n'a pas d'équivalent simple dans un document Pandoc concaténé
  (pas de "première page" adressable), il est donc volontairement
  laissé tel quel plutôt que de deviner une cible fausse
- les ancres déjà "nues" (ex: [texte](#ancre)) : déjà valides pour
  Pandoc, rien à faire

Usage (même convention que les autres scripts de book/macro/) :
    python3 resolve_internal_links.py < input.md > output.md
    (contrairement à resolve_image_paths.py, ce script n'a PAS besoin
    du chemin du fichier source : il ne fait que retirer un préfixe,
    il ne recalcule pas un chemin relatif)
"""

import re
import sys

# Capture [texte](cible) mais pas ![alt](cible) grâce au (?<!!)
LINK_PATTERN = re.compile(r'(?<!!)\[([^\]]*)\]\(([^)\s]+)\)')


def rewrite_target(match: "re.Match") -> str:
    text, target = match.group(1), match.group(2)

    if target.startswith(("http://", "https://", "mailto:")):
        return match.group(0)

    if ".md#" in target:
        anchor = target.split("#", 1)[1]
        return f"[{text}](#{anchor})"

    return match.group(0)


def convert(text: str) -> str:
    return LINK_PATTERN.sub(rewrite_target, text)


def main():
    content = sys.stdin.read()
    sys.stdout.write(convert(content))


if __name__ == "__main__":
    main()
