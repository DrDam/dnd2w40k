-- Reconstruit tous les Table Pandoc (tableaux simples ET paires de
-- tableaux MkDocs Material "grid") en tabular/booktabs, en les attachant
-- à leur légende si une légende (paragraphe en italique, généralement
-- avec l'attribut {.table-title}) la précède immédiatement.
--
-- Style commun à tous les tableaux (voir \newcolumntype L/C/R et
-- \tablefontsize/\tablecaptionfontsize dans book/preamble.tex) :
--   - colonnes à largeur fixe avec centrage vertical du texte
--   - alignement horizontal sans justification forcée (texte multi-ligne
--     aligné à gauche/droite/centré, jamais étiré bord à bord)
--   - lignes de corps alternées légèrement grisées (gray!12 / white).
--     Implémenté via des \rowcolor explicites par ligne (mode standard
--     et mode wide) -- et non \rowcolors, pour ne jamais dépendre d'un
--     compteur global qui pourrait être perturbé par l'environnement
--     englobant. En mode "grid", où chaque tabular est imbriqué comme
--     cellule d'un tabular englobant, \rowcolor déborderait sur toute
--     la hauteur de ligne du tabular englobant ; on utilise alors
--     \cellcolor par cellule (voir `table_to_tabular_lines`).
--   - taille de police configurable séparément pour la légende
--     (\tablecaptionfontsize) et le contenu du tableau (\tablefontsize),
--     toutes deux définies dans book/preamble.tex. Pour réduire la
--     police des tableaux dans tout le document, modifier uniquement
--     ces deux commandes dans le préambule -- aucun changement requis
--     ici.
--
-- Trois modes de rendu, suivant la légende qui précède le(s) tableau(x) :
--
--   1. Légende seule + tableau -> mode "standard" : le tableau reste DANS
--      LE FLUX de la colonne courante (pas de float), collé à sa légende.
--      Largeur calée sur \columnwidth (largeur d'UNE colonne de texte en
--      mode twocolumn -- PAS \textwidth, qui vaut la largeur de la PAGE
--      entière et ferait largement déborder le tableau hors de sa
--      colonne).
--      Utilise `supertabular` (PAS `tabular` dans un center) : si le
--      tableau est trop long pour la colonne/page courante, il continue
--      automatiquement en haut de la colonne/page suivante, en répétant
--      la légende (suffixée de "(suite)") ET l'en-tête de colonnes --
--      titre "collant" qui suit le tableau partout où il se coupe.
--      C'est pour cette répétition automatique que `supertabular` est
--      utilisé ici plutôt qu'un simple `tabular` : un `tabular` coupé en
--      plein milieu par un saut de page/colonne laisse sa suite orpheline,
--      sans légende ni en-tête (comportement observé avant ce filtre).
--
--   2. Légende avec flag .wide + tableau -> mode "wide" : le tableau a
--      VRAIMENT besoin de pleine largeur (plus de colonnes que ne peut
--      en contenir une seule colonne de texte). Syntaxe :
--        *Titre*{.table-title .wide}
--      Passe par `strip` (package cuted) : le tableau reste exactement à
--      sa place dans le flux (pas un float qui peut se déplacer), avec
--      la légende et le tableau dans le MÊME bloc \strip pour qu'ils ne
--      puissent jamais se retrouver séparés par une coupure de page.
--      Largeur calée sur \textwidth (pleine largeur de page).
--      Reste en `tabular` classique (pas de titre "collant" multi-page) :
--      `supertabular` gère sa pagination au niveau \output de LaTeX, ce
--      qui entre en conflit avec le patch de \output déjà effectué par
--      `cuted` pour `strip` -- combiner les deux n'est pas fiable. En
--      pratique, les tableaux .wide visent la largeur plutôt que la
--      hauteur (sinon ils seraient en mode standard), donc ce cas reste
--      rare ; à surveiller si un tableau .wide devient trop long pour
--      une page.
--
--      Limite connue de `strip` : contrairement à un float, il ne peut
--      PAS reporter son contenu sur la page suivante s'il ne rentre pas
--      dans l'espace RESTANT de la page courante (pas la page entière).
--      Un tableau .wide un peu haut, arrivant au milieu d'une page déjà
--      bien remplie, déclenche alors "LaTeX Warning: Optional argument
--      of \twocolumn too tall" et "Text page N contains only floats".
--      Si ça arrive, ajouter .newpage à la légende :
--        *Titre*{.table-title .wide .newpage}
--      force un \clearpage juste avant le tableau, qui démarre alors en
--      haut d'une page vierge avec le \textheight complet disponible.
--      Ne règle pas le cas extrême d'un tableau plus haut qu'une page
--      entière (aucune solution avec `strip` dans ce cas : il faudrait
--      alléger le tableau, ou revenir à un vrai float `table*`).

--
--   3. Légende + Div MkDocs Material `grid` contenant DEUX tableaux ->
--      mode "grid" : les deux tableaux s'affichent côte à côte sous une
--      légende commune, chacun avec sa propre largeur calée sur la
--      moitié de \columnwidth.
--      Reste en `tabular` classique (pas de titre "collant" multi-page) :
--      `supertabular` ne peut pas être imbriqué comme cellule d'un autre
--      tabular, ce qui est la structure même du mode grid (deux tableaux
--      côte à côte). En pratique ces tableaux sont volontairement courts
--      (paires de listes de coûts/valeurs), donc le risque de coupure
--      reste faible.
--
-- Sans légende précédente, le tableau garde l'ancien comportement
-- (choix automatique table/table* selon une heuristique de largeur,
-- en float [!t]), pour ne pas casser les tableaux sans titre.
--
-- Note : `longtable` (par défaut chez Pandoc) lève une erreur fatale en
-- mode `twocolumn` ("longtable not in 1-column mode") -- c'est pour
-- cette raison que ce filtre reconstruit entièrement les tableaux en
-- `tabular`/`supertabular` plutôt que de s'appuyer sur la sortie LaTeX
-- par défaut de Pandoc.

-- Convertit un alignement Pandoc + une largeur (fraction de la largeur
-- de référence, voir `width_unit` plus bas) en spécification de colonne
-- LaTeX, en utilisant les types personnalisés L{}/C{}/R{} (définis dans
-- le préambule via \newcolumntype) qui combinent :
--   - une largeur fixe (permet le retour à la ligne automatique)
--   - un centrage vertical (via m{} sous-jacent)
--   - un alignement horizontal sans justification forcée (\raggedright
--     pour la gauche, \raggedleft pour la droite, \centering pour le centre)
local function align_to_coltype(align, width, width_unit)
  local letter
  if align == "AlignLeft" then letter = "L"
  elseif align == "AlignRight" then letter = "R"
  elseif align == "AlignCenter" then letter = "C"
  else letter = "L" end
  return string.format("%s{%.4f\\%s}", letter, width, width_unit)
end

-- Calcule une largeur par colonne, en se basant sur les ColWidth fournis
-- par Pandoc quand disponibles (cas des pipe-tables avec séparateurs
-- ajustés), sinon répartition égale. `total_target` contrôle la largeur
-- totale visée (fraction de l'unité de largeur), pour laisser de la
-- marge aux séparateurs entre colonnes et éviter tout débordement.
local function compute_column_widths(tbl, total_target)
  local n = #tbl.colspecs
  local widths = {}
  local has_explicit_widths = true

  for _, colspec in ipairs(tbl.colspecs) do
    local w = colspec[2]
    if type(w) == "number" then
      table.insert(widths, w)
    else
      has_explicit_widths = false
      table.insert(widths, 1.0 / n)
    end
  end

  if not has_explicit_widths then
    for i = 1, n do widths[i] = 1.0 / n end
  end

  local sum_widths = 0
  for _, w in ipairs(widths) do sum_widths = sum_widths + w end

  local result = {}
  for _, w in ipairs(widths) do
    table.insert(result, (w / sum_widths) * total_target)
  end
  return result
end

local function blocks_to_latex(blocks)
  local doc = pandoc.Pandoc(blocks)
  local s = pandoc.write(doc, "latex")
  s = s:gsub("\n", " ")
  s = s:gsub("%s+$", "")
  -- Nettoie les résidus d'attributs Markdown non interprétés par Pandoc
  -- (ex: {.table-title} ou {.table-title .wide}, utiles pour le style/flag
  -- côté MkDocs Material mais sans signification pour Pandoc/LaTeX).
  -- Les accolades sont échappées par pandoc.write (\{ \}).
  s = s:gsub("%s*\\%{%.[%a%-%s\"=.]*\\%}%s*$", "")
  return s
end

local function blocks_to_plain_text(blocks)
  local doc = pandoc.Pandoc(blocks)
  return pandoc.utils.stringify(doc)
end

-- Détecte si un bloc "légende candidate" porte le flag .wide
local function has_wide_flag(block)
  local text = blocks_to_plain_text({block})
  return text:find("%.wide") ~= nil
end

-- Détecte si un bloc "légende candidate" porte réellement le marqueur
-- .table-title (ex: *Titre*{.table-title} ou *Titre*{.table-title .wide}).
--
-- INDISPENSABLE : sans ce test, TOUT paragraphe de texte normal placé
-- juste avant un Table (une simple phrase d'intro, par exemple) était
-- pris à tort pour la légende du tableau qui suit -- puisque
-- is_caption_candidate ne testait auparavant que le TYPE de bloc
-- (Para/Plain), jamais son contenu. Un tableau volontairement "sans
-- titre" mais précédé d'un paragraphe ordinaire se retrouvait donc
-- avec ce paragraphe transformé en légende (mise en petite italique,
-- perdu comme texte normal), et le tableau basculait à tort en mode
-- "captioned" (supertabular) au lieu du mode standalone attendu.
local function has_table_title_flag(block)
  local text = blocks_to_plain_text({block})
  return text:find("%.table%-title") ~= nil
end

-- Détecte si un bloc "légende candidate" porte le flag .newpage
-- (ex: *Titre*{.table-title .wide .newpage}). Réservé aux tableaux
-- .wide -- voir captioned_table_wide pour la raison d'être de ce flag :
-- contrairement à un float, `strip` (package cuted) ne peut PAS
-- basculer un tableau trop grand sur la page suivante s'il ne rentre
-- pas dans l'espace restant de la page courante -- il doit tenir dans
-- l'espace RESTANT, pas dans une page pleine. D'où "LaTeX Warning:
-- Optional argument of \twocolumn too tall" et "Text page N contains
-- only floats" quand un tableau .wide un peu haut arrive au milieu
-- d'une page déjà partiellement remplie. .newpage force un
-- \clearpage juste avant le strip, pour que le tableau démarre en
-- haut d'une page vierge et dispose ainsi du \textheight complet --
-- ce qui ne garantit pas qu'il tienne (un tableau plus haut qu'une
-- page entière reste impossible avec `strip`, quoi qu'il arrive), mais
-- résout le cas courant où il ne manque que peu de place.
local function has_newpage_flag(block)
  local text = blocks_to_plain_text({block})
  return text:find("%.newpage") ~= nil
end

-- Construit la liste des lignes de corps (hors en-tête), chacune sous la
-- forme { cells = {...} }, pour pouvoir ensuite leur appliquer un
-- \rowcolor explicite une à une.
local function collect_body_rows(tbl)
  local rows = {}
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        table.insert(cells, blocks_to_latex(cell.contents))
      end
      table.insert(rows, cells)
    end
  end
  return rows
end

-- Génère le bloc tabular complet (en-tête + corps), avec :
--   - colonnes à largeur fixe et centrage vertical (types L/C/R)
--   - lignes de corps alternées légèrement grisées, via un \rowcolor
--     explicite devant chaque ligne de corps (la première ligne de
--     corps est colorée, donnant l'alternance gris/blanc/gris/...).
--     Ce choix (plutôt que \rowcolors) évite tout désalignement de
--     l'alternance lorsque le tableau est imbriqué dans un autre
--     environnement (center, strip...).
--
--     ATTENTION toutefois : \rowcolor colore toute la hauteur de la
--     ligne PHYSIQUE du tabular le plus EXTÉRIEUR dans lequel il se
--     trouve. Si ce tabular est lui-même imbriqué comme cellule d'un
--     autre tabular (cas du mode "grid", deux tableaux côte à côte),
--     la couleur déborde sur toute la hauteur de la ligne du tabular
--     englobant et casse l'alternance des DEUX tableaux. Dans ce cas
--     précis, utiliser `use_cellcolor=true` pour colorer chaque
--     cellule individuellement (\cellcolor, qui reste local à la
--     cellule) plutôt que la ligne entière.
--
-- `total_target` : largeur totale visée pour l'ensemble des colonnes,
-- en fraction de `width_unit` (\columnwidth pour les tableaux en flux
-- normal d'une colonne de texte, \textwidth pour les tableaux .wide en
-- pleine page, ou une largeur explicite pour les tableaux en grille).
local function table_to_tabular_lines(tbl, total_target, width_unit, use_cellcolor)
  width_unit = width_unit or "columnwidth"
  local widths = compute_column_widths(tbl, total_target)
  local col_specs = {}
  for idx, colspec in ipairs(tbl.colspecs) do
    table.insert(col_specs, align_to_coltype(tostring(colspec[1]), widths[idx], width_unit))
  end
  local col_spec = table.concat(col_specs, "")

  local lines = {
    "\\begin{tabular}{@{}" .. col_spec .. "@{}}",
  }

  for _, row in ipairs(tbl.head.rows) do
    local cells = {}
    for _, cell in ipairs(row.cells) do
      table.insert(cells, "\\textbf{" .. blocks_to_latex(cell.contents) .. "}")
    end
    table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
  end

  local body_rows = collect_body_rows(tbl)
  for idx, cells in ipairs(body_rows) do
    local shaded = (idx % 2 == 1)
    if shaded and use_cellcolor then
      local colored_cells = {}
      for _, cell in ipairs(cells) do
        table.insert(colored_cells, "\\cellcolor{gray!12}" .. cell)
      end
      table.insert(lines, table.concat(colored_cells, " & ") .. " \\\\[\\tablerowsep]")
    else
      if shaded then
        table.insert(lines, "\\rowcolor{gray!12}")
      end
      table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
    end
  end

  table.insert(lines, "\\end{tabular}")
  return table.concat(lines, "\n")
end

-- Variante de `table_to_tabular_lines` pour `supertabular` : sépare la
-- définition de l'en-tête de colonnes (répété à chaque nouvelle page/
-- colonne via \tablehead) de l'environnement supertabular lui-même, qui
-- ne contient que les lignes de corps.
--
-- IMPORTANT : la légende est insérée comme une ligne \multicolumn dans
-- \tablefirsthead/\tablehead, PAS via la commande \tablecaption de
-- supertabular -- \tablecaption préfixe automatiquement la légende
-- d'un numéro de table ("Table 1.1: ..."), ce qui ne correspond pas au
-- style des autres tableaux du document (légende en italique simple,
-- sans numérotation -- voir \begin{center}...\end{center} dans
-- `captioned_table_wide`/`captioned_table_grid`, qui n'utilisent pas
-- \caption non plus). Garder \tablecaption inutilisé évite aussi toute
-- incohérence de numérotation entre tableaux "standard" (qui en
-- auraient une) et "wide"/"grid" (qui n'en ont pas).
--
-- ATTENTION -- piège \multicolumn + colortbl dans \tablehead/\tablefirsthead :
-- englober le \multicolumn{}{}{...} de la ligne de légende dans un
-- groupe explicite {\tablecaptionfontsize ...} casse la compilation
-- avec une erreur fatale "Misplaced \omit" (LaTeX reste bloqué en
-- attente de saisie, même en -interaction=nonstopmode). C'est un
-- conflit connu entre colortbl (chargé ici via \usepackage[table]{xcolor},
-- nécessaire pour \rowcolor) et la macro \multispan/\omit interne aux
-- en-têtes de supertabular : le groupe { } autour du \multicolumn
-- perturbe la portée que colortbl attend pour patcher \omit. La parade
-- consiste à placer \tablecaptionfontsize comme premier token DANS le
-- contenu de la cellule (4e argument du \multicolumn), jamais dans un
-- groupe qui englobe le \multicolumn lui-même -- la taille de police
-- reste bien appliquée (elle se propage normalement à tout ce qui suit
-- dans la cellule), seule la position du groupe change.
-- Par symétrie, \tablefontsize (qui s'applique au CORPS du tableau,
-- cellules de \begin{supertabular}...\end{supertabular}) est émis tel
-- quel AVANT \tablefirsthead, donc hors de toute structure de tableau :
-- aucun risque équivalent à cet endroit.
--
-- AUTRE PIÈGE -- \emph imbriqué dans \textit (annule l'italique) :
-- `caption_latex` provient du Markdown source via Pandoc, qui rend
-- *texte*{.table-title} en \emph{texte} (PAS \textit{texte}). \emph
-- BASCULE l'style ambiant au lieu de le forcer : un \emph{...} imbriqué
-- DANS un \textit{...} repasse donc en romain au lieu de rester en
-- italique. Le suffixe "(suite)" est donc ajouté en \textit{(suite)}
-- séparé, juxtaposé après caption_latex -- jamais en englobant
-- caption_latex dans un \textit{%s (suite)} (qui désitaliciserait toute
-- la légende d'origine).
--
-- `caption_latex` est répété dans \tablefirsthead (légende normale, une
-- seule fois en haut du tableau) et \tablehead (légende suffixée de
-- "(suite)", répétée à chaque continuation page/colonne suivante).
-- Retourne une chaîne LaTeX complète prête à insérer dans le flux.
-- caption_latex est optionnel (nil ou "" = pas de légende) : dans ce
-- cas, aucune ligne de titre n'est générée/répétée -- seul l'en-tête de
-- colonnes du tableau (\tablefirsthead/\tablehead) est répété en cas de
-- coupure entre page/colonne. C'est ce qui permet aux tableaux SANS
-- *Titre*{.table-title} de rester eux aussi dans le flux via
-- supertabular (voir standalone_table_to_latex), au lieu de repasser
-- par un float table/table* qui peut se déplacer hors de sa place
-- d'origine dans le texte.
local function table_to_supertabular_lines(tbl, total_target, width_unit, caption_latex)
  width_unit = width_unit or "columnwidth"
  local widths = compute_column_widths(tbl, total_target)
  local col_specs = {}
  for idx, colspec in ipairs(tbl.colspecs) do
    table.insert(col_specs, align_to_coltype(tostring(colspec[1]), widths[idx], width_unit))
  end
  local col_spec = table.concat(col_specs, "")
  local ncols = #tbl.colspecs

  local header_cells = {}
  for _, row in ipairs(tbl.head.rows) do
    local cells = {}
    for _, cell in ipairs(row.cells) do
      table.insert(cells, "\\textbf{" .. blocks_to_latex(cell.contents) .. "}")
    end
    table.insert(header_cells, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
  end
  local header_block = table.concat(header_cells, "\n")

  local has_caption = caption_latex ~= nil and caption_latex ~= ""

  local firsthead, contthead
  if has_caption then
    firsthead = string.format(
      "\\tablefirsthead{\\multicolumn{%d}{@{}l@{}}{\\tablecaptionfontsize %s}\\\\[0.3em]\n%s}",
      ncols, caption_latex, header_block
    )
    contthead = string.format(
      "\\tablehead{\\multicolumn{%d}{@{}l@{}}{\\tablecaptionfontsize %s \\textit{(suite)}}\\\\[0.3em]\n%s}",
      ncols, caption_latex, header_block
    )
  else
    firsthead = string.format("\\tablefirsthead{%s}", header_block)
    contthead = string.format("\\tablehead{%s}", header_block)
  end

  local lines = {
    -- \begingroup/\endgroup (et non \begin{table}/center/strip, qui
    -- casseraient la pagination interne de supertabular -- voir notes
    -- ci-dessus) : seul moyen de scoper \tablefontsize sans perturber
    -- le patch du \output que supertabular effectue pour sa
    -- continuation automatique entre pages/colonnes. Sans ce groupe,
    -- \tablefontsize (= \small) est une déclaration LaTeX globale qui
    -- ne se referme jamais : elle "fuit" sur tout le reste du document
    -- après ce tableau (réduisant la taille de police de tout ce qui
    -- suit), puisque ni \tablefirsthead/\tablehead/\tabletail ni
    -- \begin{supertabular}...\end{supertabular} n'ouvrent de groupe.
    "\\begingroup",
    "\\tablefontsize",
    firsthead,
    contthead,
    "\\tabletail{}",
    "\\tablelasttail{}",
    "\\begin{supertabular}{@{}" .. col_spec .. "@{}}",
  }

  local body_rows = collect_body_rows(tbl)
  for idx, cells in ipairs(body_rows) do
    local shaded = (idx % 2 == 1)
    if shaded then
      table.insert(lines, "\\rowcolor{gray!12}")
    end
    table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
  end

  table.insert(lines, "\\end{supertabular}")
  table.insert(lines, "\\endgroup")
  return table.concat(lines, "\n")
end


-- Tableau SANS légende précédente (pas de *Titre*{.table-title} juste
-- avant) : comportement par défaut = pleine colonne ET dans le flux,
-- exactement comme un tableau avec légende en mode standard -- la seule
-- différence est l'absence de ligne de titre.
--
-- Historique : ce cas passait par un float `\begin{table}[!t]` (ou
-- `table*` selon une heuristique de largeur, désormais supprimée -- voir
-- note plus bas dans l'historique de ce fichier). Un float peut se
-- déplacer hors de sa place d'origine dans le texte (LaTeX le pousse en
-- haut de la page/colonne suivante s'il ne tient pas). Ce défaut restait
-- invisible tant que le bug de is_caption_candidate absorbait presque
-- tous les tableaux narratifs en mode "captioned" (supertabular, qui
-- LUI reste dans le flux) -- une fois ce bug corrigé, les tableaux
-- réellement sans titre se sont mis à "sauter" hors de leur place.
--
-- Fix : on réutilise directement table_to_supertabular_lines (le même
-- mécanisme "dans le flux" que les tableaux captionnés), simplement
-- sans légende -- voir le paramètre caption_latex optionnel de cette
-- fonction. Le tableau reste ainsi à sa place exacte dans le texte,
-- avec pagination automatique (en-tête de colonnes répété) s'il déborde
-- sur la page/colonne suivante.
--
-- Un tableau standalone n'a normalement aucun moyen d'être marqué .wide
-- dans ce document (le flag .wide n'est lu que sur le paragraphe de
-- légende, voir has_wide_flag) -- mais on vérifie tout de même
-- tbl.attr.classes au cas où une vraie syntaxe de légende Pandoc
-- (`: Légende {.wide}`) serait utilisée un jour, ce qui peuple
-- réellement l'Attr du Table lui-même. Dans ce cas, même traitement que
-- captioned_table_wide (strip, pleine largeur), mais sans légende.
local function standalone_table_to_latex(tbl)
  local wide = tbl.attr and tbl.attr.classes and tbl.attr.classes:includes("wide")

  if wide then
    local tabular = table_to_tabular_lines(tbl, 0.87, "textwidth")
    local latex = "\\begin{strip}\n\\centering\n\\tablefontsize\n" .. tabular .. "\n\\end{strip}"
    return pandoc.RawBlock("latex", latex)
  end

  return pandoc.RawBlock("latex", table_to_supertabular_lines(tbl, 0.98, "columnwidth"))
end

-- Tableau AVEC légende préalable, mode flux normal (par défaut).
-- Largeur calée sur \columnwidth : en mode twocolumn, \textwidth est la
-- largeur de la PAGE entière (deux colonnes), alors que ce tableau reste
-- dans une seule colonne -- utiliser \textwidth ici ferait déborder le
-- tableau bien au-delà de sa colonne.
-- Utilise `supertabular` (voir `table_to_supertabular_lines`) : permet
-- au tableau de continuer en haut de la colonne/page suivante si trop
-- long, en répétant légende + en-tête de colonnes ("titre collant").
-- Pas de \begin{center}...\end{center} englobant ici : supertabular
-- gère lui-même son insertion dans le flux de la page (un center autour
-- casserait sa pagination interne).
local function captioned_table_inline(caption_latex, tbl)
  return pandoc.RawBlock("latex",
    table_to_supertabular_lines(tbl, 0.98, "columnwidth", caption_latex))
end

-- Tableau AVEC légende préalable, mode pleine largeur (flag .wide).
-- Utilise `strip` (package cuted) plutôt qu'un float table* : le tableau
-- reste exactement à sa place dans le flux (texte 2 colonnes avant/après,
-- tableau pleine largeur entre les deux), sans jamais se déplacer.
-- Légende et tableau sont regroupés dans un seul \begin{strip}...\end{strip}
-- avec \nopagebreak entre les deux, pour qu'ils ne puissent jamais être
-- séparés par une coupure de page.
local function captioned_table_wide(caption_latex, tbl, newpage)
  local tabular = table_to_tabular_lines(tbl, 0.87, "textwidth")
  local clearpage = newpage and "\\mbox{}\\clearpage\n" or ""
  local latex = string.format([[
%s\begin{strip}
\centering
{\tablecaptionfontsize %s}\par
\vspace{0.3em}
\nopagebreak
\tablefontsize
%s
\end{strip}]], clearpage, caption_latex, tabular)
  return pandoc.RawBlock("latex", latex)
end

-- Tableau AVEC légende préalable, mode "grid" : Div MkDocs Material
-- `grid` contenant deux tableaux, affichés côte à côte sous une légende
-- commune. Chaque tableau vise la moitié de \columnwidth (avec marge
-- pour l'espacement entre les deux).
-- Englobé dans un \begin{samepage}...\end{samepage} : ce bloc reste
-- VOLONTAIREMENT en `tabular` classique (pas de titre "collant" multi-
-- page -- supertabular ne peut pas être imbriqué comme cellule d'un
-- autre tabular, ce qui est la structure même de ce mode). `samepage`
-- empêche LaTeX de couper le bloc en deux entre une page/colonne et la
-- suivante (légende d'un côté, tableaux orphelins de l'autre -- défaut
-- observé avant ce correctif) ; en pratique ces tableaux sont courts
-- (quelques lignes de coûts/valeurs), donc les forcer entiers sur une
-- même colonne/page ne pose pas de problème de place.
local function captioned_table_grid(caption_latex, tbl1, tbl2)
  local tabular1 = table_to_tabular_lines(tbl1, 0.46, "columnwidth", true)
  local tabular2 = table_to_tabular_lines(tbl2, 0.46, "columnwidth", true)
  local latex = string.format([[
\begin{samepage}
\begin{center}
{\tablecaptionfontsize %s}\par
\vspace{0.3em}
\tablefontsize
\begin{tabular}{cc}
%s & %s
\end{tabular}
\end{center}
\end{samepage}]], caption_latex, tabular1, tabular2)
  return pandoc.RawBlock("latex", latex)
end

local function grid_is_two_tables(div)
  if #div.content ~= 2 then return false end
  return div.content[1].t == "Table" and div.content[2].t == "Table"
end

function Pandoc(doc)
  local blocks = doc.blocks
  local new_blocks = {}
  local i = 1

  while i <= #blocks do
    local b = blocks[i]
    local next_b = blocks[i + 1]

    local is_caption_candidate = (b.t == "Para" or b.t == "Plain")
      and has_table_title_flag(b)
    local next_is_table = next_b and next_b.t == "Table"
    local next_is_grid_pair = next_b and next_b.t == "Div"
      and next_b.classes:includes("grid")
      and grid_is_two_tables(next_b)

    if is_caption_candidate and next_is_grid_pair then
      local caption_latex = blocks_to_latex({b})
      table.insert(new_blocks, captioned_table_grid(caption_latex, next_b.content[1], next_b.content[2]))
      i = i + 2 -- consomme la légende ET le Div grid

    elseif is_caption_candidate and next_is_table then
      local caption_latex = blocks_to_latex({b})
      local wide = has_wide_flag(b)

      if wide then
        local newpage = has_newpage_flag(b)
        table.insert(new_blocks, captioned_table_wide(caption_latex, next_b, newpage))
      else
        table.insert(new_blocks, captioned_table_inline(caption_latex, next_b))
      end
      i = i + 2 -- consomme la légende ET le tableau

    elseif b.t == "Table" then
      table.insert(new_blocks, standalone_table_to_latex(b))
      i = i + 1
    else
      table.insert(new_blocks, b)
      i = i + 1
    end
  end

  doc.blocks = new_blocks
  return doc
end
