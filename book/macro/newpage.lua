-- Insère un \clearpage juste avant tout Header (de n'importe quel niveau)
-- OU toute image isolée sur sa propre ligne, portant la classe
-- ".newpage", pour forcer ce titre/cette image en haut d'une nouvelle
-- page dans le PDF.
--
-- Syntaxe Markdown (compatible MkDocs Material via l'extension
-- attr_list, qui ignore silencieusement les classes qu'elle ne connaît
-- pas -- même mécanisme que {.table-title} ou {.wide}) :
--
--   ## Mon titre {.newpage}
--
--   ![Légende](chemin/vers/image.jpg){.newpage}
--
-- IMPORTANT pour les images : l'attribut doit être collé DIRECTEMENT
-- contre la parenthèse fermante, SANS ESPACE -- ![Alt](img.jpg){.newpage}
-- et non ![Alt](img.jpg) {.newpage}. Avec un espace, attr_list ne
-- reconnaît plus l'attribut comme appartenant à l'image : il est alors
-- traité comme du texte littéral "{.newpage}" affiché tel quel dans le
-- PDF, et le saut de page n'est jamais inséré. Cette règle est la même
-- pour {.wide} (voir wide_image.lua).
--
-- Le Header reste un vrai Header (donc toujours présent dans la table
-- des matières / le sommaire) ; l'image reste une image normale (et
-- peut être combinée avec .wide -- voir plus bas). Dans les deux cas,
-- seul un \clearpage est inséré juste avant.
--
-- Compatible avec part_cover.lua : un Header de niveau 1 peut porter à
-- la fois "background"/"textcolor" (page de partie) ET ".newpage" --
-- part_cover.lua insère déjà son propre \clearpage via
-- \ThisCenterWallPaper, donc ce filtre ne rajoute pas de saut de page
-- redondant dans ce cas précis.
--
-- ATTENTION -- piège \clearpage après \end{strip} : le package cuted
-- (utilisé par tables.lua et wide_image.lua pour les tableaux/images
-- .wide en pleine largeur de page) patche la routine \output de LaTeX
-- pour son fonctionnement interne. Si un \clearpage est émis JUSTE
-- APRÈS un \end{strip} (typiquement : un titre .newpage qui suit
-- immédiatement un tableau ou une image .wide), ce \clearpage est
-- silencieusement absorbé par l'état de sortie spécial laissé actif
-- par cuted -- le saut de page n'a alors aucun effet visible. La
-- parade standard consiste à insérer une boîte vide (\mbox{}) juste
-- avant le \clearpage : cela force LaTeX à clore le paragraphe courant
-- dans un état normal avant le saut de page, ce qui le sort du
-- contexte laissé par cuted. Sans effet de bord constaté dans le cas
-- normal (sans strip précédent), donc appliqué systématiquement.
--
-- Note d'ordre des filtres : ce filtre doit s'exécuter AVANT
-- wide_image.lua dans le pipeline (book.sh), pour repérer une image
-- .newpage avant qu'elle ne soit éventuellement déjà transformée en
-- \strip par wide_image.lua si elle porte aussi .wide -- sinon ce
-- filtre ne verrait plus un bloc Image mais un RawBlock latex déjà
-- généré, et ne pourrait plus y insérer son \clearpage correctement.
-- Si une image porte À LA FOIS .wide ET .newpage, le \clearpage est
-- alors inséré juste avant le \begin{strip} généré ensuite par
-- wide_image.lua.

local CLEARPAGE = pandoc.RawBlock("latex", "\\mbox{}\\clearpage")

function Header(el)
  if not el.classes:includes("newpage") then
    return el
  end

  -- Évite un \clearpage en double si le Header est aussi une page de
  -- partie avec fond d'image (déjà géré par part_cover.lua, qui insère
  -- son propre \clearpage via \ThisCenterWallPaper).
  if el.level == 1 and el.attributes["background"] then
    return el
  end

  return { CLEARPAGE, el }
end

-- Détecte un Para/Plain qui contient EXACTEMENT une seule image (pas de
-- texte autour), avec la classe .newpage sur cette image. Reproduit le
-- même pattern de détection que wide_image.lua pour .wide.
local function newpage_image_block(block)
  if block.t ~= "Para" and block.t ~= "Plain" then
    return false
  end
  if #block.content ~= 1 or block.content[1].t ~= "Image" then
    return false
  end
  return block.content[1].classes:includes("newpage")
end

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  for _, b in ipairs(blocks) do
    if newpage_image_block(b) then
      table.insert(new_blocks, CLEARPAGE)
    end
    table.insert(new_blocks, b)
  end

  doc.blocks = new_blocks
  return doc
end
