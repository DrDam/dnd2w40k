-- Transforme une image isolée sur sa propre ligne et portant la classe
-- ".wide" en bannière PLEINE LARGEUR DE PAGE, même en mode twocolumn.
--
-- Syntaxe Markdown :
--
--   ![Légende optionnelle](chemin/vers/image.jpg){.wide}
--
-- Comportement par défaut (SANS .wide) : inchangé, l'image reste dans
-- le flux de la colonne courante, dimensionnée à \columnwidth (sa
-- largeur naturelle si elle est plus petite). C'est déjà le
-- comportement de base de Pandoc avec -f markdown-implicit_figures
-- (pas de figure flottante), donc ce filtre ne touche pas du tout aux
-- images sans ".wide".
--
-- Comportement AVEC .wide : l'image passe par `strip` (package cuted,
-- déjà utilisé par tables.lua pour les tableaux .wide), ce qui lui
-- permet de s'étaler sur toute la largeur de la page EXACTEMENT à sa
-- place dans le flux (pas un float qui peut se déplacer en haut/bas de
-- page). Si une légende est présente (texte alt), elle est affichée en
-- italique sous l'image, dans le même bloc \strip, pour ne jamais s'en
-- détacher lors d'une coupure de page.
--
-- Largeur visée : 0.95\textwidth (pleine page, avec une petite marge
-- de sécurité -- même valeur que les tableaux standalone .wide dans
-- tables.lua).
--
-- ATTENTION -- piège \maxwidth/\maxheight de Pandoc : le template
-- Pandoc fixe des valeurs PAR DÉFAUT globales pour le package graphicx
-- via \setkeys{Gin}{width=\maxwidth,height=\maxheight,keepaspectratio},
-- où \maxheight est plafonné à la hauteur NATURELLE de l'image. Si on
-- ne précise que `width=` dans \includegraphics (comme ferait un appel
-- "naïf"), l'image hérite quand même de `height=\maxheight` et de
-- `keepaspectratio=true` -- LaTeX retient alors la contrainte la PLUS
-- restrictive des deux (largeur ET hauteur), ce qui revient à garder
-- quasiment la taille native de l'image, même avec une bannière .wide
-- explicitement demandée à 95% de la largeur de page. Il faut donc
-- TOUJOURS écraser explicitement `height=` (à \textheight, qui n'est
-- jamais plus restrictif que la largeur visée pour une bannière) en
-- plus de `width=`, pour neutraliser cet héritage.

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

-- Détecte un Para qui contient EXACTEMENT une seule image (pas de texte
-- autour), avec la classe .wide sur cette image.
local function is_wide_image_para(block)
  if block.t ~= "Para" and block.t ~= "Plain" then
    return nil
  end
  if #block.content ~= 1 or block.content[1].t ~= "Image" then
    return nil
  end
  local img = block.content[1]
  if not img.classes:includes("wide") then
    return nil
  end
  return img
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

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  for _, b in ipairs(blocks) do
    local img = is_wide_image_para(b)
    if img then
      table.insert(new_blocks, wide_image_to_latex(img))
    else
      table.insert(new_blocks, b)
    end
  end

  doc.blocks = new_blocks
  return doc
end
