-- Gère le rendu de TOUTES les images isolées sur leur propre ligne
-- (![alt](chemin){attrs} seul sur sa ligne, sans texte autour) :
-- ajoute systématiquement la légende (texte alt) en italique sous
-- l'image quand elle est présente, et gère en plus le cas ".wide" en
-- bannière pleine largeur de page.
--
-- Syntaxe Markdown :
--
--   ![Légende](chemin/vers/image.jpg)              -> dans le flux, centrée dans sa colonne, légende dessous
--   ![Légende](chemin/vers/image.jpg){.wide}        -> pleine largeur de page, légende dessous
--
-- Pourquoi ce filtre est nécessaire même pour les images SANS .wide :
-- book.sh utilise -f markdown-implicit_figures (le "-" DÉSACTIVE
-- l'extension), ce qui fait que Pandoc ne génère JAMAIS de bloc Figure
-- avec \caption automatique pour une image seule sur sa ligne -- elle
-- devient un \includegraphics brut, SANS AUCUNE LÉGENDE, même si un
-- texte alt est présent dans le Markdown. Ce choix était nécessaire
-- pour que ce filtre (et newpage.lua) puissent détecter une image
-- isolée comme un Para contenant un seul inline Image (un bloc Figure
-- aurait une structure différente, non détectée). En contrepartie,
-- ce filtre doit lui-même réinjecter la légende manquante pour TOUTES
-- les images, pas seulement celles en .wide.
--
-- Comportement AVEC .wide : l'image passe par `strip` (package cuted),
-- ce qui lui permet de s'étaler sur toute la largeur de la page
-- EXACTEMENT à sa place dans le flux (pas un float qui peut se
-- déplacer en haut/bas de page). Largeur visée : 0.95\textwidth.
--
-- Comportement SANS .wide : l'image reste dans le flux de la colonne
-- courante, centrée, dimensionnée à \columnwidth par défaut (sa
-- largeur naturelle si elle est plus petite, gérée par keepaspectratio).
--
-- Hauteur personnalisée (images SANS .wide uniquement) : l'attribut
-- Markdown standard `height=` permet de fixer une hauteur précise tout
-- en conservant le ratio d'aspect (la largeur s'ajuste automatiquement,
-- sans jamais dépasser \columnwidth grâce à keepaspectratio) :
--
--   ![Légende](chemin/vers/image.jpg){height=4cm}
--
-- Unités acceptées : toutes celles de LaTeX (cm, pt, in, ...). Sans cet
-- attribut, la hauteur par défaut reste \textheight (= pas de limite de
-- hauteur réelle, seule la largeur de colonne contraint l'image).
-- Combinable avec .newpage (voir newpage.lua) ; non pertinent pour les
-- images .wide (qui visent toujours le maximum de hauteur disponible,
-- \textheight, pour leur largeur de bannière).
--
-- Dans les deux cas, si une légende (texte alt) est présente, elle est
-- affichée en italique sous l'image, dans le MÊME bloc LaTeX (center
-- ou strip), pour ne jamais s'en détacher lors d'une coupure de page.
--
-- ATTENTION -- piège \maxwidth/\maxheight de Pandoc : le template
-- Pandoc fixe des valeurs PAR DÉFAUT globales pour le package graphicx
-- via \setkeys{Gin}{width=\maxwidth,height=\maxheight,keepaspectratio},
-- où \maxheight est plafonné à la hauteur NATURELLE de l'image. Si on
-- ne précise que `width=` dans \includegraphics (comme ferait un appel
-- "naïf"), l'image hérite quand même de `height=\maxheight` et de
-- `keepaspectratio=true` -- LaTeX retient alors la contrainte la PLUS
-- restrictive des deux (largeur ET hauteur), ce qui revient à garder
-- quasiment la taille native de l'image, même avec une largeur cible
-- explicite. Il faut donc TOUJOURS écraser explicitement `height=` (à
-- \textheight par défaut, ou à la valeur demandée via l'attribut
-- height= sinon) en plus de `width=`, pour neutraliser cet héritage.

local WIDE_IMAGE_WIDTH = 0.95

local function caption_to_latex(caption_inlines)
  if #caption_inlines == 0 then
    return nil
  end
  local doc = pandoc.Pandoc({pandoc.Plain(caption_inlines)})
  local s = pandoc.write(doc, "latex")
  s = s:gsub("\n", " ")
  s = s:gsub("%s+$", "")
  return s
end

-- Détecte un Para/Plain qui contient EXACTEMENT une seule image (pas de
-- texte autour). Retourne l'objet Image si trouvé, nil sinon.
local function isolated_image(block)
  if block.t ~= "Para" and block.t ~= "Plain" then
    return nil
  end
  if #block.content ~= 1 or block.content[1].t ~= "Image" then
    return nil
  end
  return block.content[1]
end

local function wide_image_to_latex(img)
  local caption_latex = caption_to_latex(img.caption)
  local parts = {
    "\\begin{strip}",
    "\\centering",
    string.format(
      "\\includegraphics[width=%.2f\\textwidth,height=\\textheight,keepaspectratio]{%s}",
      WIDE_IMAGE_WIDTH, img.src
    ),
  }
  if caption_latex then
    table.insert(parts, "\\par\\vspace{0.3em}")
    table.insert(parts, "\\emph{" .. caption_latex .. "}")
  end
  table.insert(parts, "\\end{strip}")
  return pandoc.RawBlock("latex", table.concat(parts, "\n"))
end

local function normal_image_to_latex(img)
  local caption_latex = caption_to_latex(img.caption)
  -- Hauteur personnalisée via l'attribut Markdown height=, sinon
  -- \textheight par défaut (pas de limite réelle, voir note ci-dessus).
  -- Validation basique : un nombre suivi d'une unité LaTeX connue, pour
  -- éviter d'injecter une valeur malformée dans le LaTeX généré (et
  -- silencieusement ignorer/retomber sur \textheight si la syntaxe ne
  -- correspond pas à ce qu'on attend).
  local height = img.attributes["height"]
  if not height or not height:match("^%d+%.?%d*%a+$") then
    height = "\\textheight"
  end
  local parts = {
    "\\begin{center}",
    string.format(
      "\\includegraphics[width=\\columnwidth,height=%s,keepaspectratio]{%s}",
      height, img.src
    ),
  }
  if caption_latex then
    table.insert(parts, "\\par\\vspace{0.3em}")
    table.insert(parts, "\\emph{" .. caption_latex .. "}")
  end
  table.insert(parts, "\\end{center}")
  return pandoc.RawBlock("latex", table.concat(parts, "\n"))
end

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  for _, b in ipairs(blocks) do
    local img = isolated_image(b)
    if img and img.classes:includes("wide") then
      table.insert(new_blocks, wide_image_to_latex(img))
    elseif img then
      table.insert(new_blocks, normal_image_to_latex(img))
    else
      table.insert(new_blocks, b)
    end
  end

  doc.blocks = new_blocks
  return doc
end
