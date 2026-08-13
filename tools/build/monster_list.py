#!/usr/bin/env python3
"""
Parcourt une arborescence Monstres/Groupe/[Sous-Groupe/]*.md et met à jour,
dans chaque fichier 000-intro.md, le tableau "Liste des fiches" listant tous
les monstres présents dans le même dossier et dans ses sous-dossiers.

Utilisation :
    python3 generate_monster_tables.py /chemin/vers/Monstres

Le script est idempotent : on peut le relancer autant de fois que nécessaire,
il remplacera le tableau existant sous l'ancre plutôt que de le dupliquer.
"""

import os
import re
import sys
from dataclasses import dataclass
from typing import List, Optional

ANCHOR_TEXT = "*Liste des fiches* {.table-title .wide}"
INTRO_FILENAME = "000-intro.md"

HEADING_RE = re.compile(r"^####\s+(.+?)\s*\{(.+?)\}\s*$", re.MULTILINE)
ANCHOR_ID_RE = re.compile(r"#(\S+)")
DESC_RE = re.compile(r"^\*(.+?)\*\s*$", re.MULTILINE)
POWER_RE = re.compile(r"\*\*Facteur de puissance\*\*\s*:\s*(\d+(?:/\d+)?)\s*\((.+?)\)")

# Titre de niveau 3 (### Titre) éventuellement suivi d'attributs pandoc {.newpage ...}
H3_RE = re.compile(r"^###(?!#)\s+(.+?)\s*(?:\{.*\})?\s*$", re.MULTILINE)
LEADING_ARTICLE_RE = re.compile(r"^(?:Les|Des|Le|La|L['’])\s*", re.IGNORECASE)


def strip_leading_article(title: str) -> str:
    """Retire un article français en tête de titre (Les/Des/Le/La/L')."""
    return LEADING_ARTICLE_RE.sub("", title, count=1).strip()


_subgroup_title_cache = {}


def get_subgroup_title(subgroup_dir: str, fallback_name: str) -> str:
    """Récupère le titre de niveau 3 (### ...) du 000-intro.md d'un sous-dossier.

    Retombe sur le nom du dossier si le fichier ou le titre est introuvable.
    """
    if subgroup_dir in _subgroup_title_cache:
        return _subgroup_title_cache[subgroup_dir]

    intro_path = os.path.join(subgroup_dir, INTRO_FILENAME)
    title = fallback_name
    if os.path.isfile(intro_path):
        with open(intro_path, "r", encoding="utf-8") as f:
            text = f.read()
        match = H3_RE.search(text)
        if match:
            title = strip_leading_article(match.group(1).strip())
        else:
            print(f"  [!] Aucun titre de niveau 3 (### ...) trouvé dans {intro_path}, "
                  f"utilisation du nom de dossier \"{fallback_name}\".")
    else:
        print(f"  [!] Pas de {INTRO_FILENAME} dans {subgroup_dir}, "
              f"utilisation du nom de dossier \"{fallback_name}\" pour la colonne Groupe.")

    _subgroup_title_cache[subgroup_dir] = title
    return title


def parse_power_value(power_text: str) -> float:
    """Convertit '1', '1/2' ou '1/8' en valeur numérique pour le tri."""
    if "/" in power_text:
        numerator, denominator = power_text.split("/", 1)
        return int(numerator) / int(denominator)
    return float(power_text)


@dataclass
class Monster:
    name: str
    anchor: str
    filename: str
    power_num: float
    power_str: str
    description: str
    group: Optional[str] = None  # nom du sous-dossier relatif à l'intro traité


def parse_monster_file(path: str) -> Optional[Monster]:
    """Extrait les métadonnées d'une fiche de monstre."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()

    heading_match = HEADING_RE.search(text)
    if not heading_match:
        print(f"  [!] Impossible de trouver le titre (#### Nom {{...}}) dans {path}, fichier ignoré.")
        return None
    name = heading_match.group(1).strip()
    attrs = heading_match.group(2).strip()

    anchor_match = ANCHOR_ID_RE.search(attrs)
    if not anchor_match:
        print(f"  [!] Impossible de trouver l'ancre (#id) dans le titre de {path}, fichier ignoré.")
        return None
    anchor = anchor_match.group(1).strip()

    power_match = POWER_RE.search(text)
    if not power_match:
        print(f"  [!] Impossible de trouver le Facteur de puissance dans {path}, fichier ignoré.")
        return None
    power_num = parse_power_value(power_match.group(1))
    power_str = f"{power_match.group(1)} ({power_match.group(2)})"

    # La description (ligne en italique) se trouve après l'ouverture du bloc
    # <div class="monster ...">, pour éviter de capturer une autre ligne en
    # italique présente dans le texte narratif au-dessus.
    div_start = text.find('<div class="monster')
    search_zone = text[div_start:] if div_start != -1 else text
    desc_match = DESC_RE.search(search_zone)
    description = desc_match.group(1).strip() if desc_match else ""

    return Monster(
        name=name,
        anchor=anchor,
        filename=os.path.basename(path),
        power_num=power_num,
        power_str=power_str,
        description=description,
    )


def find_monster_files(directory: str) -> List[str]:
    """Liste les .md d'un dossier (hors 000-intro.md), non récursif."""
    result = []
    for entry in sorted(os.listdir(directory)):
        full = os.path.join(directory, entry)
        if os.path.isfile(full) and entry.lower().endswith(".md") and entry != INTRO_FILENAME:
            result.append(full)
    return result


def collect_monsters_recursive(intro_dir: str) -> List[Monster]:
    """Récupère tous les monstres sous intro_dir (ce dossier + sous-dossiers)."""
    monsters: List[Monster] = []
    for root, dirs, files in os.walk(intro_dir):
        dirs.sort()
        rel = os.path.relpath(root, intro_dir)
        if rel == ".":
            group = None
        else:
            first_component = rel.split(os.sep)[0]
            subgroup_dir = os.path.join(intro_dir, first_component)
            group = get_subgroup_title(subgroup_dir, first_component)

        for fname in sorted(files):
            if fname.lower().endswith(".md") and fname != INTRO_FILENAME:
                m = parse_monster_file(os.path.join(root, fname))
                if m:
                    m.group = group
                    monsters.append(m)
    return monsters


def build_table(monsters: List[Monster]) -> str:
    """Construit le tableau markdown, trié par facteur de puissance puis nom."""
    with_group = any(m.group is not None for m in monsters)

    monsters_sorted = sorted(monsters, key=lambda m: (m.power_num, m.name.casefold()))

    lines = []
    if with_group:
        lines.append("| Facteur de puissance | Groupe | Nom | Description |")
        lines.append("|:-:|---| -----|------------|")
        for m in monsters_sorted:
            group_display = m.group if m.group is not None else ""
            lines.append(
                f"| {m.power_str} | {group_display} | [{m.name}]({m.filename}#{m.anchor}) | {m.description} |"
            )
    else:
        lines.append("| Facteur de puissance | Nom | Description |")
        lines.append("|:-:|-----|------------|")
        for m in monsters_sorted:
            lines.append(
                f"| {m.power_str} | [{m.name}]({m.filename}#{m.anchor}) | {m.description} |"
            )

    return "\n".join(lines) + "\n"


def update_intro_file(path: str, monsters: List[Monster]) -> None:
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines(keepends=True)

    anchor_idx = None
    for i, line in enumerate(lines):
        if line.strip() == ANCHOR_TEXT:
            anchor_idx = i
            break

    if anchor_idx is None:
        # L'ancre n'existe pas : on la crée en fin de fichier.
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        if lines and lines[-1].strip() != "":
            lines.append("\n")
        lines.append(ANCHOR_TEXT + "\n")
        anchor_idx = len(lines) - 1
        print(f"  [i] Ancre \"{ANCHOR_TEXT}\" absente de {path}, elle a été créée en fin de fichier.")

    if not monsters:
        print(f"  [i] Aucun monstre trouvé sous {os.path.dirname(path)}, tableau non généré.")
        return

    table_text = build_table(monsters)

    # Repère un éventuel tableau déjà présent juste après l'ancre (en sautant
    # les lignes vides) pour le remplacer.
    i = anchor_idx + 1
    while i < len(lines) and lines[i].strip() == "":
        i += 1
    table_start = i
    table_end = i
    while table_end < len(lines) and lines[table_end].lstrip().startswith("|"):
        table_end += 1

    new_lines = lines[: anchor_idx + 1]
    new_lines.append("\n")
    new_lines.append(table_text)
    # Conserve ce qui suivait l'ancien tableau (contenu ultérieur du fichier)
    remainder = lines[table_end:]
    # Évite d'accumuler des lignes vides superflues au tout début du reste
    while remainder and remainder[0].strip() == "":
        remainder.pop(0)
    if remainder:
        new_lines.append("\n")
        new_lines.extend(remainder)

    new_content = "".join(new_lines)
    if not new_content.endswith("\n"):
        new_content += "\n"

    with open(path, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"  [+] {path} mis à jour ({len(monsters)} monstre(s)).")


def process_tree(root_dir: str) -> None:
    _subgroup_title_cache.clear()
    intro_paths = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if INTRO_FILENAME in filenames:
            intro_paths.append(dirpath)

    for intro_dir in sorted(intro_paths):
        intro_path = os.path.join(intro_dir, INTRO_FILENAME)
        print(f"Traitement de {intro_path} ...")
        monsters = collect_monsters_recursive(intro_dir)
        update_intro_file(intro_path, monsters)


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 generate_monster_tables.py /chemin/vers/Monstres")
        sys.exit(1)

    root_dir = sys.argv[1]
    if not os.path.isdir(root_dir):
        print(f"Le dossier {root_dir} n'existe pas.")
        sys.exit(1)

    process_tree(root_dir)


if __name__ == "__main__":
    main()
