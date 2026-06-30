-- statblock.lua
-- Transforme les fenced divs {.monster} et {.statline} en LaTeX
-- pour produire un encadré "bloc monstre" façon livre de règles D&D.
--
-- POINT CRITIQUE -- pourquoi tout est sérialisé en UN SEUL RawBlock :
-- ce filtre tourne EN PREMIER dans le pipeline (book.sh), avant
-- tables.lua, newpage.lua, wide_image.lua, part_cover.lua. Si ce
-- filtre se contentait de "déballer" le Div .monster (renvoyer une
-- liste de blocs à la place du Div, comme le ferait `return el.content`),
-- Pandoc aplatit cette liste directement dans doc.blocks au niveau
-- racine du document -- le Div n'existe plus comme conteneur. Les
-- blocs internes (Table de .statline, Header "Actions", etc.)
-- deviennent alors des blocs de premier niveau ordinaires, et les
-- filtres suivants ne peuvent plus distinguer "ce Table fait partie
-- d'un bloc monstre" de "ce Table est un vrai tableau du manuscrit" --
-- tables.lua le retransforme alors en `table*`/`supertabular` (float
-- pleine largeur), ce qui détruit la mise en page du cadre.
-- En sérialisant tout le contenu en un seul pandoc.RawBlock("latex", ...)
-- ici même, le bloc monstre devient un texte LaTeX opaque pour tous
-- les filtres suivants : ils n'y voient plus ni Table, ni Header, ni
-- Div, et ne peuvent donc plus le retoucher par erreur.
--
-- Corollaire : .statline ne peut pas non plus être traité par son
-- propre Div(el) indépendant comme avant -- il doit être résolu ICI,
-- À L'INTÉRIEUR du traitement de .monster, AVANT la sérialisation
-- finale. D'où la fonction `render_statline` appliquée directement
-- sur les Div enfants pendant la construction du bloc monstre, plutôt
-- qu'une fonction Div(el) générique séparée qui s'exécuterait après
-- coup (et ne verrait jamais ce .statline, puisqu'il n'existera déjà
-- plus en tant que Div une fois remonté jusqu'au niveau racine).
--
-- Pourquoi le tableau .statline est reconstruit à la main en `tabular`
-- (et jamais laissé en `longtable`, sortie par défaut de Pandoc pour
-- tout Table) : ce document compile en `documentclass: book` avec
-- l'option `twocolumn` (metadata.yaml) -- `longtable` lève une erreur
-- fatale "longtable not in 1-column mode" dans ce mode. C'est la même
-- raison qui pousse tables.lua à reconstruire tous les autres tableaux
-- du document en tabular/supertabular plutôt que de s'appuyer sur la
-- sortie LaTeX par défaut de Pandoc -- voir tables.lua pour le détail.

local function is_format(fmt)
  return FORMAT:match(fmt)
end

local function escape_latex(s)
  return (s:gsub("\\", "\\textbackslash{}")
            :gsub("([%%&_#{}$])", "\\%1"))
end

-- Sérialise une liste d'inlines Pandoc (ex: le contenu d'une cellule)
-- en LaTeX, en réutilisant le writer Pandoc plutôt qu'en réinventant
-- la conversion gras/italique -- même approche que blocks_to_latex
-- dans tables.lua.
local function inlines_to_latex(inlines)
  local doc = pandoc.Pandoc({pandoc.Plain(inlines)})
  local s = pandoc.write(doc, "latex")
  s = s:gsub("\n", " "):gsub("%s+$", "")
  return s
end

-- Construit un \begin{tabular}...\end{tabular} simple (PAS longtable,
-- voir note en tête de fichier) à partir d'un Pandoc Table -- conçu
-- spécifiquement pour la ligne de 6 caractéristiques (FOR/DEX/CON/...),
-- toujours courte et à largeur de colonnes égales.
--
-- IMPORTANT -- marge invisible \tabcolsep : tabular insère 2\tabcolsep
-- (12pt par défaut) entre CHAQUE paire de colonnes adjacentes, en plus
-- de la largeur déclarée dans chaque C{...}. Pour 6 colonnes (5
-- espacements internes), cela ajoute ~60pt invisibles non comptés dans
-- STATLINE_WIDTH_TARGET*\linewidth -- observé en test, un Overfull
-- \hbox subsiste même à 0.97\linewidth tant que ce point n'est pas
-- traité. On neutralise \tabcolsep localement (\setlength dans le
-- \begin{tabular} via un groupe) plutôt que d'essayer de deviner une
-- fraction de compensation qui resterait fragile si ncols change.
local STATLINE_WIDTH_TARGET = 0.88

local function statline_table_to_tabular(tbl)
  local ncols = #tbl.colspecs
  local col_width = STATLINE_WIDTH_TARGET / ncols
  local col_spec = string.rep(string.format("C{%.4f\\linewidth}", col_width), ncols)

  local lines = {
    "{\\setlength{\\tabcolsep}{2pt}",
    "\\begin{tabular}{@{}" .. col_spec .. "@{}}",
  }

  for _, row in ipairs(tbl.head.rows) do
    local cells = {}
    for _, cell in ipairs(row.cells) do
      table.insert(cells, inlines_to_latex(pandoc.utils.blocks_to_inlines(cell.contents)))
    end
    table.insert(lines, table.concat(cells, " & ") .. " \\\\")
  end
  table.insert(lines, "\\midrule")

  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        table.insert(cells, inlines_to_latex(pandoc.utils.blocks_to_inlines(cell.contents)))
      end
      table.insert(lines, table.concat(cells, " & ") .. " \\\\")
    end
  end

  table.insert(lines, "\\end{tabular}}")
  return table.concat(lines, "\n")
end

-- Rendu d'un Div .statline (toujours appelé depuis l'intérieur du
-- traitement de .monster, jamais comme Div(el) indépendant -- voir
-- note en tête de fichier). Repère le premier Table à l'intérieur du
-- Div et l'enveloppe dans l'environnement \statline.
local function render_statline(div)
  local parts = {"\\begin{statline}"}
  for _, block in ipairs(div.content) do
    if block.t == "Table" then
      table.insert(parts, statline_table_to_tabular(block))
    end
  end
  table.insert(parts, "\\end{statline}")
  return table.concat(parts, "\n")
end

-- Rendu d'un Header interne au bloc monstre : nom du monstre, ou
-- sous-titre (Actions, Réactions, Traits légendaires...).
--
-- IMPORTANT -- le niveau du "nom du monstre" N'EST PAS figé à 1 : selon
-- l'endroit du document où le bloc .monster apparaît, son premier Header
-- peut être de n'importe quel niveau Markdown (####, #####, ...) -- ce
-- niveau dépend de la profondeur de la section qui l'entoure (ex: une
-- fiche de personnage où le bloc est niché sous Sorcier > Aptitudes >
-- Familier). Seul ce qui compte : le PREMIER Header rencontré dans le
-- Div .monster est le nom (-> \monstername), tout Header de niveau
-- STRICTEMENT PLUS PROFOND (numériquement supérieur) qui suit est une
-- sous-section interne (-> \monstersection, avec sa ligne de séparation
-- -- voir preamble.tex). `name_level` est déterminé une fois par
-- render_monster (premier Header vu) et transmis ici à chaque appel.
local function render_header(el, name_level)
  local title = pandoc.utils.stringify(el.content)
  if el.level <= name_level then
    return "\\monstername{" .. title .. "}"
  end
  return "\\monstersection{" .. title .. "}"
end

-- Rendu générique d'un bloc "ordinaire" (Para, Plain, HorizontalRule...)
-- à l'intérieur du bloc monstre : délégué au writer LaTeX standard de
-- Pandoc, qui gère déjà correctement gras/italique/sauts de ligne/etc.
local function render_generic_block(block)
  local doc = pandoc.Pandoc({block})
  local s = pandoc.write(doc, "latex")
  return (s:gsub("%s+$", ""))
end

-- Rendu d'un bloc "ordinaire" (Para, Plain, HorizontalRule...) déjà
-- identifié comme appartenant à une section donnée -- factorisé hors
-- de render_generic_block pour être réutilisé par render_section.
local function render_block(block, name_level)
  if block.t == "Header" then
    return render_header(block, name_level)
  elseif block.t == "Div" and block.classes:includes("statline") then
    return render_statline(block)
  else
    return render_generic_block(block)
  end
end

-- Rendu d'un groupe de blocs (une "section" : soit l'intro du monstre --
-- nom + stats de tête avant le premier sous-titre --, soit un sous-titre
-- ##### et tout son contenu jusqu'au sous-titre suivant) en l'enveloppant
-- dans \begin{samepage}...\end{samepage}.
--
-- POURQUOI samepage ICI -- voir la demande qui a motivé ce filtre : le
-- bloc monstre (\monsterblock) est maintenant `breakable` (préamble),
-- ce qui autorise tcolorbox à le faire courir sur la page/colonne
-- suivante s'il ne tient pas en entier -- mais SANS verrou
-- supplémentaire, ce point de coupure peut tomber n'importe où, y
-- compris EN PLEIN MILIEU d'une section (ex: entre deux lignes du
-- paragraphe "Métamorphe" sous Traits). En enveloppant chaque section
-- dans son propre samepage, LaTeX refuse d'y insérer une coupure : la
-- coupure de page ne peut alors se produire qu'ENTRE deux samepage
-- consécutifs, c'est-à-dire exactement à la frontière d'un #####.
-- Même mécanisme déjà utilisé par admonition.lua pour les encadrés
-- note/tip/warning (un seul samepage là, ici un par section).
--
-- Limite assumée : si une section individuelle (ex: un Traits très
-- long) dépasse à elle seule la hauteur d'une page/colonne, samepage
-- ne peut pas faire de miracle -- elle débordera quand même. C'est
-- un compromis volontaire : pour un bloc personnage de taille
-- raisonnable, les sections individuelles tiennent largement sur une
-- page, et le gain (jamais de coupure moche en plein milieu d'un
-- paragraphe) l'emporte largement sur ce cas limite.
local function render_section(blocks, name_level)
  local parts = {"\\begin{samepage}"}
  for _, block in ipairs(blocks) do
    table.insert(parts, render_block(block, name_level))
  end
  table.insert(parts, "\\end{samepage}")
  return table.concat(parts, "\n\n")
end

-- Construit le LaTeX complet d'un Div .monster : parcourt son contenu
-- au premier niveau (Header, Div .statline, Para, HorizontalRule...),
-- regroupe les blocs par section (voir render_section), délègue
-- chaque type de bloc au bon renderer, et assemble le tout en une
-- seule chaîne, encadrée par \begin{monsterblock}...\end{monsterblock}.
local function render_monster(div)
  -- Niveau du premier Header rencontré = niveau du "nom du monstre"
  -- (voir note dans render_header). nil tant qu'aucun Header n'a
  -- encore été vu -- fixé une seule fois, à la première rencontre,
  -- AVANT le regroupement en sections (un Header de ce niveau ne doit
  -- jamais déclencher une nouvelle section, voir boucle ci-dessous).
  local name_level = nil
  for _, block in ipairs(div.content) do
    if block.t == "Header" then
      name_level = block.level
      break
    end
  end

  -- Regroupement : un nouveau groupe démarre à chaque Header strictement
  -- plus profond que name_level (un sous-titre ##### Traits/Actions/...) ;
  -- tout le reste s'accumule dans le groupe courant.
  local groups = {}
  local current = {}
  for _, block in ipairs(div.content) do
    if block.t == "Header" and name_level and block.level > name_level then
      if #current > 0 then
        table.insert(groups, current)
      end
      current = {}
    end
    table.insert(current, block)
  end
  if #current > 0 then
    table.insert(groups, current)
  end

  local parts = {"\\begin{monsterblock}"}
  for _, group in ipairs(groups) do
    table.insert(parts, render_section(group, name_level))
  end
  table.insert(parts, "\\end{monsterblock}")
  return table.concat(parts, "\n\n")
end

function Div(el)
  if not el.classes:includes("monster") then
    return nil
  end

  if not is_format("latex") then
    -- HTML / autres formats : on laisse le div tel quel,
    -- MkDocs (markdown HTML natif) le rendra en <div class="monster">.
    return nil
  end

  -- Sérialisation en UN SEUL RawBlock opaque -- voir note en tête de
  -- fichier pour la raison impérative de ce choix.
  local monster_latex = render_monster(el)

  -- Bloc monstre .wide : pleine largeur de PAGE plutôt que pleine
  -- largeur de COLONNE (comportement par défaut). Réutilise le même
  -- mécanisme que les images .wide (wide_image.lua) et les tableaux
  -- .wide (tables.lua) : l'environnement `strip` du package cuted,
  -- qui étale son contenu sur toute la largeur de la page à sa place
  -- exacte dans le flux, sans devenir un float susceptible de se
  -- déplacer. Le tcolorbox \monsterblock se redimensionne tout seul
  -- (il est défini en \linewidth, qui vaut alors la largeur de page
  -- complète à l'intérieur de strip) -- aucun changement requis côté
  -- preamble.tex pour ce cas.
  --
  -- \mbox{} avant \begin{strip} : même précaution que newpage.lua et
  -- part_cover.lua face au piège \clearpage/strip de cuted (voir
  -- newpage.lua pour le détail) -- ici appliquée par prudence avant
  -- l'ouverture du strip lui-même, au cas où le bloc monstre .wide
  -- suivrait immédiatement un autre tableau/image .wide.
  if el.classes:includes("wide") then
    monster_latex = "\\mbox{}\\begin{strip}\n" .. monster_latex .. "\n\\end{strip}"
  end

  return pandoc.RawBlock("latex", monster_latex)
end
