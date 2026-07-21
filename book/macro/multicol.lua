-- Transforme un Div {.multicol cols="N"} (généré par
-- book/macro/multicol_markers.py à partir d'un marqueur
-- <!-- multicol:N --> ... <!-- endmulticol --> invisible sur MkDocs)
-- en une zone à N colonnes, PAGINÉE nativement par le package
-- `multicol` (pas de limite d'une page, contrairement aux tentatives
-- précédentes -- voir historique complet ci-dessous).
--
-- HISTORIQUE COMPLET -- trois approches essayées avant celle-ci :
--
--   1. `\begin{multicols}{N}` imbriqué dans le mode twocolumn ACTIF du
--      document : `multicol` prévient lui-même que ça "may not work"
--      -- confirmé, contenu perdu dans un cas de test.
--   2. `\onecolumn ... \begin{multicols}{N} ... \twocolumn`, MAIS avec
--      \onecolumn placé juste APRÈS le titre de chapitre (à
--      l'emplacement du Div dans le Markdown, immédiatement après
--      "## Pouvoirs Technologique") : la pagination fonctionnait, mais
--      \onecolumn force TOUJOURS un saut de page, même si la page
--      courante ne contient que le titre -- résultat : une page
--      quasiment blanche entre le titre et la liste (constaté en
--      usage réel).
--   3. Plusieurs `\mbox{}\begin{strip}...\end{strip}` (cuted)
--      consécutifs, un par "page" de contenu estimée par un calcul de
--      poids approximatif (nombre de lignes) : le calcul, même
--      calibré empiriquement sur du contenu réel, s'est avéré trop
--      fragile -- un chunk légèrement sous-estimé en hauteur réelle a
--      fait PERDRE SILENCIEUSEMENT des items de liste (une colonne
--      tronquée en plein milieu, sans le moindre avertissement de
--      compilation). cuted/\strip n'étant pas conçu pour gérer
--      lui-même un dépassement de page de façon fiable dans ce cas de
--      figure, cette approche est trop risquée pour être conservée.
--
-- SOLUTION RETENUE : \onecolumn/\twocolumn (comme la tentative 2, donc
-- pagination fiable et native via `multicol`, aucun risque de perte de
-- contenu -- multicol utilise \vsplit en interne, le même mécanisme
-- fiable qu'utilise LaTeX pour la pagination normale, pas une
-- estimation approximative faite à l'avance), MAIS avec \onecolumn
-- déplacé pour s'exécuter JUSTE AVANT le Header qui précède le Div
-- (typiquement le titre de chapitre "## Pouvoirs Technologique"),
-- PLUTÔT QU'après.
--
-- Pourquoi ce déplacement élimine la page blanche : \onecolumn
-- contient lui-même un \clearpage. Si ce \clearpage s'exécute APRÈS
-- que le titre de chapitre a déjà été composé (tentative 2), il clôt
-- la page courante (qui ne contient que ce titre) et en ouvre une
-- nouvelle pour la suite -- d'où la page quasi blanche. En plaçant
-- \onecolumn AVANT le Header, son \clearpage coïncide avec le saut de
-- page que \chapter déclenche de toute façon en interne (tout
-- \chapter commence sur une page neuve) : les deux ne s'additionnent
-- pas, un seul saut de page a lieu, et le titre ET la liste
-- apparaissent ensemble sur la même page fraîche -- vérifié par
-- compilation (titre + multicols sur la même page, page suivante
-- reprend le mode twocolumn normalement).
--
-- Ce filtre opère donc au niveau Pandoc(doc) (pas juste Div(el)) :
-- il a besoin de regarder le bloc qui PRÉCÈDE le Div dans le document
-- pour savoir s'il doit "capturer" un Header et le faire précéder de
-- \onecolumn. S'il n'y a pas de Header juste avant (cas rare), le Div
-- est traité seul, \onecolumn juste avant lui comme en tentative 2
-- (avec le risque résiduel de leger espace blanc dans ce cas précis,
-- mais cas non rencontré dans ce document).
--
-- Le filet des titres (\titlerulecore, voir preamble.tex) n'est plus
-- affecté : ce n'était pas multicol qui le cassait à l'origine, mais
-- un coefficient -1.25\baselineskip trop grand dans preamble.tex,
-- corrigé indépendamment (-0.9\baselineskip).
--
-- \raggedright DANS multicols : sans lui, la justification pleine
-- largeur sur une colonne étroite produit des espaces énormes entre
-- les mots (ex: "Programme de traduction" qui passe à la ligne).
--
-- Header/BulletList à l'intérieur du Div restent des blocs Pandoc
-- NATIFS (jamais resérialisés via pandoc.write, qui perdrait les
-- options de la ligne de commande comme --top-level-division=part).
--
-- book/preamble.tex doit charger \usepackage{multicol} (à nouveau
-- nécessaire ici, utilisé cette fois de façon sûre -- voir ci-dessus).

local DEFAULT_COLS = 3

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}

  local i = 1
  while i <= #blocks do
    local b = blocks[i]

    if b.t == "Div" and b.classes:includes("multicol") then
      local n = tonumber(b.attributes["cols"]) or DEFAULT_COLS

      -- Si le bloc déjà ajouté juste avant est un Header (typiquement
      -- le titre de chapitre), on le "récupère" : \onecolumn doit
      -- s'exécuter AVANT lui, pas après -- voir note en tête de
      -- fichier. On le retire de new_blocks pour le replacer après le
      -- \onecolumn qu'on insère à la place.
      local preceding_header = nil
      if #new_blocks > 0 and new_blocks[#new_blocks].t == "Header" then
        preceding_header = table.remove(new_blocks)
      end

      table.insert(new_blocks, pandoc.RawBlock("latex", "\\onecolumn"))
      if preceding_header then
        table.insert(new_blocks, preceding_header)
      end
      table.insert(new_blocks, pandoc.RawBlock("latex", string.format(
        "\\begin{multicols}{%d}\n\\raggedright", n
      )))
      for _, inner in ipairs(b.content) do
        table.insert(new_blocks, inner)
      end
      table.insert(new_blocks, pandoc.RawBlock("latex", "\\end{multicols}\n\\twocolumn"))
    else
      table.insert(new_blocks, b)
    end

    i = i + 1
  end

  doc.blocks = new_blocks
  return doc
end
