-- Transforme les Header de niveau 1 portant un attribut "background"
-- en page de partie avec image plein page + couleur de texte personnalisée.
--
-- Syntaxe Markdown attendue (dans book/book_titles/LivreX.md) :
--
--   # Manuel du joueur {background="book/asset/livre1.jpg" textcolor="white"}
--
-- Le Header reste un vrai Header de niveau 1 (-> \part via --top-level-division=part),
-- donc il continue d'apparaître dans la table des matières / le sommaire.
--
-- Note : \mbox{} avant \clearpage neutralise un piège connu du package
-- cuted (voir newpage.lua pour le détail), au cas où cette page de
-- partie suivrait directement un tableau ou une image .wide.
--
-- ATTENTION -- \mbox{} en tout début de document : si ce Header de
-- couverture est le TOUT PREMIER bloc du document (rien avant), un
-- \mbox{} avant le \clearpage insère une page blanche supplémentaire
-- en tête du PDF (LaTeX ouvre une page presque vide juste pour cette
-- boîte, avant de la refermer immédiatement avec le \clearpage qui
-- suit). Ce problème ne se produit que pour le tout premier bloc : dès
-- qu'un Header de couverture est précédé d'un minimum de contenu réel
-- (chapitre, paragraphe...), \mbox{} ne crée plus de page en trop. On
-- détecte donc ce cas précis (premier bloc du document) pour omettre
-- le \mbox{} uniquement à cet endroit -- ce qui est sans risque,
-- puisqu'un strip (cuted) ne peut de toute façon pas précéder le tout
-- premier bloc du document.

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  for i, el in ipairs(blocks) do
    if el.t == "Header" and el.level == 1 and el.attributes["background"] then
      local image = el.attributes["background"]
      local textcolor = el.attributes["textcolor"] or "black"
      local is_first_block = (i == 1)
      local clearpage_cmd = is_first_block and "\\clearpage" or "\\mbox{}\\clearpage"

      local wallpaper_cmd = pandoc.RawBlock("latex", string.format(
        "%s\\ThisCenterWallPaper{1}{%s}\\color{%s}",
        clearpage_cmd, image, textcolor
      ))
      local reset_color = pandoc.RawBlock("latex", "\\color{black}")

      table.insert(new_blocks, wallpaper_cmd)
      table.insert(new_blocks, el)
      table.insert(new_blocks, reset_color)
    else
      table.insert(new_blocks, el)
    end
  end

  doc.blocks = new_blocks
  return doc
end
