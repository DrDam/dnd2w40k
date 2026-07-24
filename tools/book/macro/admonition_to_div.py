#!/usr/bin/env python3
"""
Préprocesseur : convertit la syntaxe admonition MkDocs (Python-Markdown)
en "fenced divs" Pandoc, pour permettre un rendu PDF cohérent via Pandoc + filtre Lua.

Entrée (syntaxe MkDocs) :

    !!! note "Mon titre"

        Contenu indenté de 4 espaces.
        Peut faire plusieurs lignes.

        Et même plusieurs paragraphes (toujours indentés).

    Suite normale du document.

Sortie (fenced div Pandoc) :

    ::: {.note title="Mon titre"}
    Contenu indenté de 4 espaces.
    Peut faire plusieurs lignes.

    Et même plusieurs paragraphes (toujours indentés).
    :::

    Suite normale du document.

Usage :
    python admonition_to_div.py input.md > output.md
    cat input.md | python admonition_to_div.py > output.md
"""

import re
import sys

# Pattern qui capture : "!!! type" suivi optionnellement de "titre" entre guillemets
ADMONITION_START_RE = re.compile(r'^!!!\s+(\w+)(?:\s+"([^"]*)")?\s*$')


def convert(text: str) -> str:
    lines = text.split("\n")
    output = []
    i = 0
    n = len(lines)

    while i < n:
        line = lines[i]
        m = ADMONITION_START_RE.match(line)

        if m:
            adm_type, title = m.group(1), m.group(2) or ""
            i += 1

            # Sauter la/les ligne(s) vide(s) entre le marqueur et le contenu indenté
            while i < n and lines[i].strip() == "":
                i += 1

            # Collecter toutes les lignes indentées (>= 4 espaces) OU vides
            # qui appartiennent au bloc, jusqu'à une ligne non-indentée non-vide.
            body_lines = []
            while i < n:
                current = lines[i]
                if current.strip() == "":
                    body_lines.append("")
                    i += 1
                elif current.startswith("    "):
                    body_lines.append(current[4:])  # dé-indente de 4 espaces
                    i += 1
                else:
                    break

            # Supprime les lignes vides finales superflues
            while body_lines and body_lines[-1] == "":
                body_lines.pop()

            if title:
                title_escaped = title.replace('"', '\\"')
                output.append(f'::: {{.{adm_type} title="{title_escaped}"}}')
            else:
                output.append(f"::: {{.{adm_type}}}")

            output.extend(body_lines)
            output.append(":::")
            output.append("")  # ligne vide après le bloc, pour la sécurité du parsing
        else:
            output.append(line)
            i += 1

    return "\n".join(output)


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as f:
            text = f.read()
    else:
        text = sys.stdin.read()

    sys.stdout.write(convert(text))


if __name__ == "__main__":
    main()
