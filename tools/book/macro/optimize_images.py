#!/usr/bin/env python3
"""
Optimise le POIDS des images référencées dans le Markdown avant compilation
XeLaTeX, en les redimensionnant à la taille RÉELLEMENT affichée dans le PDF
(pas la taille source, souvent bien plus grande pour un usage MkDocs/web).

Pourquoi c'est possible même sans connaître les ratios à l'avance : chaque
"rôle" d'image (cover plein-page, .wide, height=Xcm, image normale) définit
une BOÎTE D'AFFICHAGE CIBLE connue (largeur de colonne, \\textwidth, hauteur
demandée...) indépendamment du ratio de l'image elle-même. On redimensionne
donc chaque image pour qu'elle TIENNE dans sa boîte cible (résolution
d'impression choisie), sans jamais l'agrandir -- exactement le comportement
de PIL Image.thumbnail() : un "fit" dans une bounding box qui préserve le
ratio, quel qu'il soit.

Usage (s'insère dans le pipeline, APRÈS resolve_image_paths.py puisqu'il a
besoin des chemins déjà résolus relativement à la racine du projet) :

    python3 book/macro/admonition_to_div.py "$src_file" \\
      | python3 book/macro/resolve_image_paths.py "$src_file" \\
      | python3 book/macro/optimize_images.py \\
      > "$dest_file"

Dépendance : Pillow (pip install pillow --break-system-packages).

Cache : les versions optimisées sont écrites dans build/optimized-assets/,
avec les dimensions cible dans le nom de fichier (une même image utilisée
dans deux rôles différents -- ex: cover ET miniature .wide -- produit donc
deux fichiers distincts, chacun optimisé pour sa propre boîte). Le cache
est invalidé automatiquement si le fichier source est plus récent que la
version en cache (mtime), donc les builds répétés ne retraitent que les
images modifiées/nouvelles.

Géométrie alignée sur book/metadata.yaml : US Letter (pas de a4paper en
classoption -> défaut extbook), marge 2.5cm (geometry: margin=2.5cm),
\\columnsep=1.5cm (book/preamble.tex). Si l'un de ces réglages change dans
metadata.yaml, recorrige PAGE_WIDTH_CM / PAGE_HEIGHT_CM / MARGIN_CM /
COLUMNSEP_CM ci-dessous en conséquence.
"""
import sys
import os
import re
import hashlib

try:
    from PIL import Image
except ImportError:
    sys.stderr.write(
        "Pillow n'est pas installé : pip install pillow --break-system-packages\n"
    )
    sys.exit(1)

# ============================================================
# CONFIG GÉOMÉTRIE -- à recouper avec book/metadata.yaml
# ============================================================
# Valeurs alignées sur book/metadata.yaml : `classoption` ne précise pas
# a4paper -> extbook/book retombent sur le format US Letter par défaut ;
# `geometry: margin=2.5cm` fixe la marge (haut/bas/gauche/droite identiques).
PAGE_WIDTH_CM = 21.59     # US Letter (8.5in), pas A4 : pas de a4paper en classoption
PAGE_HEIGHT_CM = 27.94    # US Letter (11in)
MARGIN_CM = 2.5           # geometry: margin=2.5cm
COLUMNSEP_CM = 1.5        # confirmé dans book/preamble.tex

TEXTWIDTH_CM = PAGE_WIDTH_CM - 2 * MARGIN_CM
TEXTHEIGHT_CM = PAGE_HEIGHT_CM - 2 * MARGIN_CM
COLUMNWIDTH_CM = (TEXTWIDTH_CM - COLUMNSEP_CM) / 2

DPI_TARGET = 200          # 150-200 = bon compromis PDF écran+impression; 300 = print pro
JPEG_QUALITY = 85

# BUILD_DIR est repris de la variable d'environnement du même nom (déjà
# définie dans book.sh/book-test.sh, ex: "build/test") -- il suffit donc
# de l'exporter avant l'appel au script pour que le cache d'images vive
# au même endroit que le reste du build, plutôt que sous "build/" en dur
# (utile si plusieurs builds -- test/prod -- tournent en parallèle ou si
# BUILD_DIR change de nom). Repli sur "build" si la variable est absente.
CACHE_DIR = os.path.join(os.environ.get("BUILD_DIR", "build"), "optimized-assets")

# ============================================================
# Détection du rôle de chaque image -> boîte cible (largeur_cm, hauteur_cm)
# ============================================================
IMAGE_PATTERN = re.compile(r'!\[[^\]]*\]\(([^)\s]+)\)(\{[^}]*\})?')
HEADER_BG_PATTERN = re.compile(r'\{[^}]*\bbackground="([^"]+)"[^}]*\}')
HEIGHT_ATTR_PATTERN = re.compile(r'height=(\d+\.?\d*)(cm|mm|in|pt)')


def cm(value, unit):
    value = float(value)
    if unit == "cm":
        return value
    if unit == "mm":
        return value / 10
    if unit == "in":
        return value * 2.54
    if unit == "pt":
        return value * 2.54 / 72.27
    return value


def target_box_cm(path, attrs):
    """Retourne (largeur_cm, hauteur_cm) : la boîte dans laquelle l'image
    sera réellement composée, selon son rôle détecté."""
    attrs = attrs or ""
    if ".wide" in attrs:
        return (0.95 * TEXTWIDTH_CM, TEXTHEIGHT_CM)
    m = HEIGHT_ATTR_PATTERN.search(attrs)
    if m:
        h_cm = cm(m.group(1), m.group(2))
        return (COLUMNWIDTH_CM, h_cm)
    # image normale (isolée ou non) : colonne x hauteur de page
    return (COLUMNWIDTH_CM, TEXTHEIGHT_CM)


def cache_path_for(src_path, box_px):
    h = hashlib.sha1(os.path.abspath(src_path).encode()).hexdigest()[:10]
    base = os.path.splitext(os.path.basename(src_path))[0]
    ext = os.path.splitext(src_path)[1].lower()
    ext = ext if ext in (".jpg", ".jpeg", ".png") else ".jpg"
    return os.path.join(
        CACHE_DIR, f"{base}-{h}-{box_px[0]}x{box_px[1]}{ext}"
    )


def optimize_image(src_path, box_cm):
    if not os.path.isfile(src_path):
        sys.stderr.write(f"Image introuvable, ignorée : {src_path}\n")
        return src_path

    box_px = (
        round(box_cm[0] / 2.54 * DPI_TARGET),
        round(box_cm[1] / 2.54 * DPI_TARGET),
    )
    dest = cache_path_for(src_path, box_px)

    if os.path.isfile(dest) and os.path.getmtime(dest) >= os.path.getmtime(src_path):
        return dest  # cache encore valide

    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with Image.open(src_path) as img:
        img = img.convert("RGB") if img.mode in ("P", "CMYK") else img
        original_size = img.size
        img.thumbnail(box_px, Image.LANCZOS)  # ne réduit jamais que si + grand
        if dest.lower().endswith((".jpg", ".jpeg")):
            img.convert("RGB").save(
                dest, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True
            )
        else:
            img.save(dest, "PNG", optimize=True)

    return dest


def rewrite_line(line):
    def replace_md_image(match):
        path, attrs = match.group(1), match.group(2)
        if path.startswith(("http://", "https://", "data:")):
            return match.group(0)
        box = target_box_cm(path, attrs)
        new_path = optimize_image(path, box)
        return match.group(0).replace(path, new_path, 1)

    def replace_header_bg(match):
        path = match.group(1)
        new_path = optimize_image(path, (PAGE_WIDTH_CM, PAGE_HEIGHT_CM))
        return match.group(0).replace(path, new_path, 1)

    line = IMAGE_PATTERN.sub(replace_md_image, line)
    line = HEADER_BG_PATTERN.sub(replace_header_bg, line)
    return line


def main():
    content = sys.stdin.read()
    out = [rewrite_line(line) for line in content.splitlines(keepends=True)]
    sys.stdout.write("".join(out))


if __name__ == "__main__":
    main()
