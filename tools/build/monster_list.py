#!/usr/bin/env python3
"""
Génère un tableau de monstres trié par FP, puis par ordre alphabétique.
Usage: python generer_tableau_monstres.py <dossier>
"""

import os
import re
from pathlib import Path

def extraire_informations(fichier_path):
    """Extrait les infos depuis le titre en tête + bloc monster."""
    with open(fichier_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Titre + slug (premier #### en tête de fichier)
    titre_match = re.search(r'####\s+(.+?)\s*\{#([^\s}]+)', content)
    if not titre_match:
        return None
    titre, slug = titre_match.group(1).strip(), titre_match.group(2)

    # 2. Localiser le bloc monster
    monster_start = content.find('<div class="monster')
    if monster_start == -1:
        return None
    monster_content = content[monster_start:]

    # 3. Description (*texte*)
    desc_match = re.search(r'^\*\s*(.+?)\s*\*$', monster_content, re.MULTILINE)
    if not desc_match:
        return None
    description = desc_match.group(1)

    # 4. Facteur de puissance
    fp_match = re.search(r'\*\*Facteur de puissance\*\*\s*:\s*([\d/]+)\s*\(([^)]+) XP\)', monster_content)
    if not fp_match:
        return None
    facteur, xp = fp_match.group(1), fp_match.group(2)

    # Conversion pour le tri
    try:
        facteur_float = float(facteur)
    except ValueError:
        if '/' in facteur:
            num, denom = facteur.split('/')
            facteur_float = float(num) / float(denom)
        else:
            facteur_float = 0

    return {
        'titre': titre,
        'slug': slug,
        'description': description,
        'facteur': facteur,
        'xp': xp,
        'facteur_float': facteur_float,
        'fichier': fichier_path.name
    }

def generer_tableau(monstres):
    """Génère le tableau Markdown trié par FP puis par nom."""
    # ✅ TRI DOUBLE : FP puis nom alphabétique
    monstres_trie = sorted(monstres, key=lambda x: (x['facteur_float'], x['titre']))
    header = "| Facteur de puissance | Nom | Description |"
    separator = "|:-:|-----|------------|"
    lignes = [header, separator]

    for m in monstres_trie:
        lien = f"[{m['titre']}]({m['fichier']}#{m['slug']})"
        ligne = f"| {m['facteur']} ({m['xp']} XP) | {lien} | {m['description']} |"
        lignes.append(ligne)
    return "\n".join(lignes)

def main(dossier):
    dossier_path = Path(dossier)
    fichiers = [f for f in os.listdir(dossier) if f.endswith('.md') and f != '000-intro.md']
    monstres = []

    for fichier in fichiers:
        info = extraire_informations(dossier_path / fichier)
        if info:
            monstres.append(info)
            print(f"✅ {info['titre']} (FP: {info['facteur']}) dans {fichier}")
        else:
            print(f"❌ Ignoré: {fichier} (format non reconnu)")

    if not monstres:
        print("❌ Aucun monstre valide trouvé.")
        return

    tableau = generer_tableau(monstres)
    intro_path = dossier_path / '000-intro.md'

    with open(intro_path, 'r', encoding='utf-8') as f:
        intro_content = f.read()

    pos = intro_content.find('<div class="table">')
    if pos == -1:
        print('❌ Balise `<div class="table">` manquante dans 000-intro.md.')
        return

    new_content = (
        intro_content[:pos + len('<div class="table">')] +
        "\n\n" + tableau + "\n\n" +
        intro_content[pos + len('<div class="table">'):]
    )

    with open(intro_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"✅ Tableau inséré dans {intro_path}")

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 2:
        print("Usage: python generer_tableau_monstres.py <dossier>")
        sys.exit(1)
    main(sys.argv[1])
