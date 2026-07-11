-- Transforme les Header de niveau 1 portant un attribut "background"
-- en page de partie avec image plein page + encart de titre en haut
-- de l'image (façon livre de règles), au lieu du titre par défaut
-- centré verticalement au milieu de l'image.
--
-- Syntaxe Markdown attendue (dans book/book_titles/LivreX.md) :
--
--   # Manuel du joueur {background="book/asset/livre1.jpg" textcolor="white"}
--
-- MÉCANISME (voir book/preamble.tex, section "PAGE DE PARTIE", pour
-- l'historique complet des deux tentatives ratées avant celle-ci) :
-- on NE laisse PAS Pandoc générer \part{...} depuis le Header --
-- \part est composé ici, directement en RawBlock, avec la forme à
-- DEUX arguments de book.cls :
--
--   \part[Titre lisible]{\PartCoverBanner{PARTIE X}{Titre}{couleur}}
--
--   - [Titre lisible] (argument optionnel) : utilisé par book.cls pour
--     la table des matières (\addcontentsline) et les signets PDF --
--     doit rester du texte normal, pas notre code tikz.
--   - {\PartCoverBanner{...}} (argument principal) : ce qui est
--     RÉELLEMENT composé sur la page -- notre encart, positionné en
--     absolu en haut de l'image via un overlay tikz. En étant
--     littéralement l'argument de \part, il est composé exactement là
--     où l'aurait été le titre par défaut : même page que l'image,
--     aucun risque de décalage sur la page suivante (\part se termine
--     toujours par un \vfil\newpage interne -- tout ce qui serait
--     inséré APRÈS le Header dans l'arbre Pandoc atterrirait sur la
--     page suivante ; en passant par l'argument de \part lui-même, ce
--     piège est évité).
--
-- \part reste le vrai \part de book.cls (pas de \titleformat, pas de
-- redéfinition) : le compteur \c@part s'incrémente normalement, le
-- patch etoolbox de remise à zéro du compteur de chapitre (book/
-- preamble.tex) continue de fonctionner sans changement.
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

-- Sérialise le contenu (inlines) du Header en LaTeX -- même technique
-- que statblock.lua/wide_image.lua (pandoc.write via un Plain
-- temporaire) : préserve gras/italique éventuels du titre Markdown
-- source, plutôt qu'un simple pandoc.utils.stringify qui les aurait
-- silencieusement perdus. Réutilisé à la fois pour l'argument
-- optionnel de \part (titre lisible, TdM/signets) et pour le titre
-- affiché dans \PartCoverBanner.
--
-- LIMITE VOLONTAIRE : un titre contenant un crochet fermant "]" (rare
-- en pratique pour un titre de partie) casserait l'argument optionnel
-- de \part -- non géré ici, pour rester simple ; à échapper à la main
-- dans le Markdown source si jamais le cas se présentait.
local function inlines_to_latex(inlines)
  local doc = pandoc.Pandoc({pandoc.Plain(inlines)})
  local s = pandoc.write(doc, "latex")
  s = s:gsub("\n", " "):gsub("%s+$", "")
  return s
end

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  for i, el in ipairs(blocks) do
    if el.t == "Header" and el.level == 1 and el.attributes["background"] then
      local image = el.attributes["background"]
      local textcolor = el.attributes["textcolor"] or "black"
      local is_first_block = (i == 1)
      local clearpage_cmd = is_first_block and "\\clearpage" or "\\mbox{}\\clearpage"

      -- Fond plein page.
      local wallpaper_cmd = pandoc.RawBlock("latex", string.format(
        "%s\\ThisCenterWallPaper{1}{%s}",
        clearpage_cmd, image
      ))

      local title_latex = inlines_to_latex(el.content)

      -- \part[titre lisible]{encart réellement affiché} -- voir note
      -- en tête de fichier. \arabic{part} est fiable ici : ce code
      -- s'exécute à l'intérieur du corps de \part, donc après son
      -- \refstepcounter{part} interne.
      local part_cmd = pandoc.RawBlock("latex", string.format(
        "\\part[%s]{\\PartCoverBanner{\\MakeUppercase{\\partname}~\\arabic{part}}{%s}{%s}}",
        title_latex, title_latex, textcolor
      ))

      table.insert(new_blocks, wallpaper_cmd)
      table.insert(new_blocks, part_cmd)
    else
      table.insert(new_blocks, el)
    end
  end

  doc.blocks = new_blocks
  return doc
end
