#!/usr/bin/env python3
"""
Réécrit les chemins d'images Markdown relatifs au FICHIER SOURCE
(convention MkDocs : ![alt](../assets/img.jpg), résolu relativement au
.md qui contient le lien) en chemins relatifs à la RACINE DU PROJET
(convention attendue par XeLaTeX, qui compile depuis la racine).

Pourquoi : dans une arborescence MkDocs, chaque page référence ses
assets relativement à elle-même (../assets/img.jpg) -- c'est correct
pour MkDocs, qui résout chaque page indépendamment. Mais Pandoc ne
réécrit jamais ces chemins : ils sont transmis tels quels au LaTeX
généré. Comme `book.sh` compile xelatex depuis la racine du projet (pas
depuis le dossier du fichier .md d'origine), un chemin relatif comme
"../assets/img.jpg" ne pointe plus vers rien d'utile une fois rendu --
il faut le réécrire en "docs/assets/img.jpg" (relatif à la racine) pour
que xelatex le retrouve.

Usage :
    python3 resolve_image_paths.py <chemin_du_fichier_source.md>
    (lit sur stdin le Markdown déjà préprocessé, écrit sur stdout)

Concrètement dans book.sh, s'insère dans le pipeline de préprocessing,
après (ou avant, l'ordre entre les deux scripts n'a pas d'importance
puisqu'ils opèrent sur des aspects disjoints du texte) admonition_to_div.py :

    python3 book/macro/admonition_to_div.py "$src_file" \
      | python3 book/macro/resolve_image_paths.py "$src_file" \
      > "$dest_file"

Limites volontaires (pour rester simple et prévisible) :
- Ne touche qu'aux images Markdown ![alt](chemin){attrs}, pas aux
  liens classiques [texte](chemin) ni au HTML brut <img src=...>.
- Ne touche pas aux chemins déjà absolus (commençant par /) ni aux
  URLs (http://, https://, data:) -- laissés tels quels.
- Ne touche pas aux chemins qui ne contiennent aucun "../" ou "./" --
  un chemin déjà relatif à la racine (ex: docs/assets/img.jpg) est
  laissé tel quel, pour ne pas casser les cas qui fonctionnent déjà.
"""
import sys
import os
import re

IMAGE_PATTERN = re.compile(r'(!\[[^\]]*\]\()([^)\s]+)(\)|\s)')


def is_url_or_absolute(path):
    if path.startswith(('/', 'http://', 'https://', 'data:')):
        return True
    return False


def needs_resolution(path):
    # Seuls les chemins qui contiennent un "../" ou commencent par "./"
    # ont besoin d'être réécrits -- un chemin déjà relatif à la racine
    # du projet (sans ces marqueurs) est laissé tel quel.
    return '../' in path or path.startswith('./')


def resolve_path(image_path, src_file):
    src_dir = os.path.dirname(src_file)
    resolved = os.path.normpath(os.path.join(src_dir, image_path))
    # normpath utilise les séparateurs natifs (OK sous Linux/macOS) ;
    # on force des slashes pour LaTeX/Pandoc, qui préfèrent '/'.
    return resolved.replace(os.sep, '/')


def rewrite_line(line, src_file):
    def replace(match):
        prefix, path, suffix = match.group(1), match.group(2), match.group(3)
        if is_url_or_absolute(path) or not needs_resolution(path):
            return match.group(0)
        new_path = resolve_path(path, src_file)
        return prefix + new_path + suffix

    return IMAGE_PATTERN.sub(replace, line)


def main():
    if len(sys.argv) != 2:
        sys.stderr.write("Usage: resolve_image_paths.py <chemin_fichier_source.md>\n")
        sys.exit(1)

    src_file = sys.argv[1]
    content = sys.stdin.read()
    out_lines = [rewrite_line(line, src_file) for line in content.splitlines(keepends=True)]
    sys.stdout.write(''.join(out_lines))


if __name__ == '__main__':
    main()
