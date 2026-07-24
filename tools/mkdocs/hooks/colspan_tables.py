"""
Hook MkDocs : fusionne visuellement les lignes "titre de section" des
tableaux Markdown (convention déjà utilisée dans les .md :
| **Armes de corps a corps simples** | | | | | -- seule la premiere
cellule est remplie, toutes les autres sont vides) en une cellule
unique centree, avec colspan sur toute la largeur du tableau.

Meme convention, meme detection que cote Pandoc/PDF (voir
is_section_header_row dans book/macro/tables.lua) : premiere cellule
non vide ET toutes les suivantes vides -- rien d'autre ne declenche la
fusion, pour ne pas fusionner par erreur une ligne normale dont seule
la derniere colonne est vide.

Installation :
    1. Copier ce fichier dans <racine du projet>/hooks/colspan_tables.py
    2. Dans mkdocs.yml :
           hooks:
             - hooks/colspan_tables.py

Aucun changement necessaire dans les fichiers .md : la convention
| **Titre** | | | | | qui fonctionne deja est simplement mieux rendue.
"""

from bs4 import BeautifulSoup


def _is_section_header_row(cells):
    if len(cells) < 2:
        return False
    first_text = cells[0].get_text(strip=True)
    if not first_text:
        return False
    for cell in cells[1:]:
        if cell.get_text(strip=True):
            return False
    return True


def _merge_table(table):
    # Nombre de colonnes total : compte les <th> de l'entete, ou a
    # defaut le nombre de cellules de la premiere ligne du corps.
    header_row = table.find("tr")
    ncols = len(header_row.find_all(["th", "td"])) if header_row else 0
    if ncols < 2:
        return

    body = table.find("tbody") or table
    for row in body.find_all("tr", recursive=False):
        cells = row.find_all(["td", "th"], recursive=False)
        if not _is_section_header_row(cells):
            continue

        first_cell = cells[0]
        first_cell["colspan"] = str(ncols)
        # Centrage : on ajoute le style directement (pas besoin de
        # toucher au CSS du theme), en complement d'un eventuel style
        # deja pose par l'extension tables (ex: text-align: right sur
        # une colonne numerique -- on l'ecrase ici volontairement).
        existing_style = first_cell.get("style", "")
        extra = "text-align: center;"
        first_cell["style"] = (existing_style + " " + extra).strip()

        # Supprime les cellules vides restantes (deja vides par
        # construction, voir _is_section_header_row).
        for cell in cells[1:]:
            cell.decompose()


def on_page_content(html, page, config, files):
    soup = BeautifulSoup(html, "html.parser")
    for table in soup.find_all("table"):
        _merge_table(table)
    return str(soup)
