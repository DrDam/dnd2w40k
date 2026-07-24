#!/usr/bin/env python3
"""
Préprocesseur : convertit des marqueurs en commentaire HTML

    <!-- multicol:4 -->
    ... contenu ...
    <!-- endmulticol -->

en fenced div Pandoc

    ::: {.multicol cols="4"}
    ... contenu ...
    :::

Pourquoi un commentaire HTML plutôt qu'un fenced div directement dans le
Markdown source : MkDocs Material ne connaît pas la syntaxe ":::" (sauf
extension dédiée non installée ici) -- un fenced div brut s'afficherait
tel quel, en texte littéral, sur le site MkDocs. Un commentaire HTML
<!-- ... --> est en revanche silencieusement ignoré par le rendu MkDocs
(comme par tout moteur Markdown/HTML) : invisible sur le site, il ne sert
qu'à baliser la zone pour le pipeline PDF. Même logique que
admonition_to_div.py pour "!!! note", mais avec un marqueur qui n'a
aucun équivalent visuel MkDocs à préserver (contrairement aux
admonitions, qui ont un rendu MkDocs propre qu'on veut reproduire côté
PDF -- ici on veut juste écarter la zone du flux 2-colonnes normal).

Usage (à insérer dans le pipeline de préprocessing, ORDRE indifférent
par rapport à admonition_to_div.py / resolve_image_paths.py /
resolve_internal_links.py -- ce script n'opère que sur des lignes de
commentaire HTML disjointes de ce que touchent les autres) :

    python3 book/macro/admonition_to_div.py "$src_file" \\
      | python3 book/macro/multicol_markers.py \\
      | python3 book/macro/resolve_image_paths.py "$src_file" \\
      | python3 book/macro/resolve_internal_links.py \\
      | BUILD_DIR="$BUILD_DIR" python3 book/macro/optimize_images.py \\
      > "$dest_file"

Le nombre de colonnes (cols="N") est repris tel quel par
book/macro/multicol.lua ; ce script ne valide pas N (une valeur absurde
ou absente échouera simplement à la compilation LaTeX, ou retombe sur
le défaut géré côté Lua -- voir multicol.lua).
"""

import re
import sys

START_RE = re.compile(r'^\s*<!--\s*multicol\s*:\s*(\d+)\s*-->\s*$')
END_RE = re.compile(r'^\s*<!--\s*endmulticol\s*-->\s*$')


def convert(text: str) -> str:
    out_lines = []
    for line in text.split("\n"):
        m_start = START_RE.match(line)
        m_end = END_RE.match(line)
        if m_start:
            cols = m_start.group(1)
            out_lines.append(f'::: {{.multicol cols="{cols}"}}')
        elif m_end:
            out_lines.append(":::")
        else:
            out_lines.append(line)
    return "\n".join(out_lines)


def main():
    content = sys.stdin.read()
    sys.stdout.write(convert(content))


if __name__ == "__main__":
    main()
