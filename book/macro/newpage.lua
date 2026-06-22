-- Insère un \clearpage juste avant tout Header (de n'importe quel niveau)
-- portant la classe ".newpage", pour forcer ce titre en haut d'une
-- nouvelle page dans le PDF.
--
-- Syntaxe Markdown (compatible MkDocs Material via l'extension
-- attr_list, qui ignore silencieusement les classes qu'elle ne connaît
-- pas -- même mécanisme que {.table-title} ou {.wide}) :
--
--   ## Mon titre {.newpage}
--
-- Le Header reste un vrai Header (donc toujours présent dans la table
-- des matières / le sommaire), seul un \clearpage est inséré juste
-- avant.
--
-- Compatible avec part_cover.lua : un Header de niveau 1 peut porter à
-- la fois "background"/"textcolor" (page de partie) ET ".newpage" --
-- part_cover.lua insère déjà son propre \clearpage via
-- \ThisCenterWallPaper, donc ce filtre ne rajoute pas de saut de page
-- redondant dans ce cas précis.

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

  local clearpage = pandoc.RawBlock("latex", "\\clearpage")
  return { clearpage, el }
end
