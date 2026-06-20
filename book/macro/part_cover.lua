-- Transforme les Header de niveau 1 portant un attribut "background"
-- en page de partie avec image plein page + couleur de texte personnalisée.
--
-- Syntaxe Markdown attendue (dans book/book_titles/LivreX.md) :
--
--   # Manuel du joueur {background="book/asset/livre1.jpg" textcolor="white"}
--
-- Le Header reste un vrai Header de niveau 1 (-> \part via --top-level-division=part),
-- donc il continue d'apparaître dans la table des matières / le sommaire.

function Header(el)
  if el.level == 1 and el.attributes["background"] then
    local image = el.attributes["background"]
    local textcolor = el.attributes["textcolor"] or "black"

    local wallpaper_cmd = pandoc.RawBlock("latex", string.format(
      "\\ThisCenterWallPaper{1}{%s}\\color{%s}",
      image, textcolor
    ))
    local reset_color = pandoc.RawBlock("latex", "\\color{black}")

    return { wallpaper_cmd, el, reset_color }
  end
  return el
end
