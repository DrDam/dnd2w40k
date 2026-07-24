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
--      bien remplie, déclencherait alors "LaTeX Warning: Optional
--      argument of \twocolumn too tall" et "Text page N contains only
--      floats".
--
--      Solution retenue : un test CONDITIONNEL via le package
--      `needspace` (\needspace{N\baselineskip}, voir need_space_latex
--      plus bas) est inséré juste avant CHAQUE tableau .wide. Il ne
--      déclenche un saut QUE si la place manque réellement -- jamais de
--      saut de colonne/page perdu pour un petit tableau qui tenait déjà
--      largement (ex: un tableau de 3 lignes). S'il faut sauter,
--      \needspace utilise en interne le même \newpage que LaTeX
--      utiliserait spontanément en mode `twocolumn` : avance seulement
--      jusqu'à la colonne suivante si on est en colonne de gauche (sans
--      perdre le contenu de celle-ci), et seulement jusqu'à une page
--      neuve si on est déjà en colonne de droite -- jamais le
--      \clearpage complet (deux colonnes perdues) qu'utilisait une
--      version antérieure de ce filtre.
--
--      N (le nombre de lignes demandées à \needspace) est estimé
--      dynamiquement à partir du tableau réel : nombre de lignes de
--      données, plus les retours à la ligne attendus pour les cellules
--      trop longues pour leur colonne (voir count_table_rows/
--      estimate_row_lines), plus une marge de sécurité fixe
--      (NEEDSPACE_EXTRA_LINES) pour la légende et les espacements.
--
--      Remarque historique : une itération précédente de ce filtre a
--      conclu à tort que `needspace` ne fonctionnait pas du tout en
--      mode `twocolumn`, sur la base d'un test isolé utilisant un
--      \rule brut pour simuler une page presque pleine -- un \rule
--      n'alimente pas le compteur de page (\pagegoal/\pagetotal) de la
--      même façon que du texte réel composé en paragraphes, ce qui
--      faussait entièrement ce test. Un nouveau test avec du texte réel
--      (paquets `lipsum`) a confirmé que `needspace` fonctionne
--      correctement -- l'échec initial sur ce document venait en fait
--      d'une estimation de lignes trop basse (sous-estimation des
--      retours à la ligne dans les cellules), pas du mécanisme lui-même.
--
--      .newpage (flag explicite sur la légende) reste disponible en
--      complément, pour forcer un VRAI saut de PAGE (\clearpage) plutôt
--      que le comportement par défaut -- utile pour un choix éditorial
--      délibéré (tableau volontairement en tête de page) :
--        *Titre*{.table-title .wide .newpage}
--      Ne règle pas non plus le cas extrême d'un tableau plus haut
--      qu'une page entière (aucune solution avec `strip` dans ce cas :
--      il faudrait alléger le tableau, ou revenir à un vrai float
--      `table*`).

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
-- Détecte une ligne "titre de section" selon la convention déjà en
-- place dans les .md (ex : | **Armes de corps à corps simples** | | | | |) :
-- SEULE la première cellule contient du texte, toutes les autres sont
-- vides. Sert à fusionner visuellement cette ligne sur toute la
-- largeur du tableau (\multicolumn centré) au lieu de la laisser
-- éparpillée sur la première colonne avec le reste de la ligne vide.
--
-- Volontairement strict (première cellule non vide ET toutes les
-- suivantes vides) : une ligne "normale" avec juste une dernière
-- colonne vide (ex : Propriétés manquantes sur une arme) ne doit PAS
-- être fusionnée par erreur -- seule la convention "tout le reste de
-- la ligne est vide" déclenche la fusion.
local function is_section_header_row(cells)
  if #cells < 2 then
    return false
  end
  if cells[1]:gsub("%s", "") == "" then
    return false
  end
  for i = 2, #cells do
    if cells[i]:gsub("%s", "") ~= "" then
      return false
    end
  end
  return true
end

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
  local ncols = #tbl.colspecs
  for idx, cells in ipairs(body_rows) do
    local shaded = (idx % 2 == 1)
    if is_section_header_row(cells) then
      local content = "\\multicolumn{" .. ncols .. "}{c}{" .. cells[1] .. "}"
      if shaded then
        table.insert(lines, "\\rowcolor{gray!12}")
      end
      table.insert(lines, content .. " \\\\[\\tablerowsep]")
    elseif shaded and use_cellcolor then
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
-- BUDGET DE LARGEUR -- même défaut que celui corrigé dans
-- captioned_table_grid (voir sa note détaillée) : le \tabcolsep par
-- défaut (6pt) s'ajoute à la largeur RÉELLE du tableau à CHAQUE
-- jonction entre colonnes adjacentes (2x\tabcolsep par jonction), sans
-- être budgété par `total_target`. Pour un tableau à 2 colonnes (1
-- jonction), l'écart passe inaperçu ; pour un tableau à 3 colonnes ou
-- plus (2+ jonctions, ex: "Point d'expérience / Niveau / Bonus de
-- maîtrise"), il s'accumule au point de déborder visiblement dans la
-- gouttière entre colonnes de page -- constaté en test avec du texte
-- réel des deux côtés.
-- Corrigé ici en réduisant \tabcolsep localement (\tablecolsep, book/
-- preamble.tex) à l'intérieur du \begingroup/\endgroup qui scope déjà
-- \tablefontsize (voir plus bas) -- même technique que
-- \tablegridcolsep pour les tableaux "grid" et \monsterblock/
-- \statline dans book/macro/statblock.lua -- et en ramenant
-- STANDARD_TABLE_WIDTH_TARGET de 0.98 à 0.94, pour garder un peu de
-- marge même sur un tableau à plusieurs colonnes.
-- Note : ne concerne QUE ce mode "standard"/"captioned inline" (table
-- SANS légende .wide, voir standalone_table_to_latex/
-- captioned_table_inline) -- le mode "wide" (table_to_tabular_lines,
-- 0.87 de \textwidth = pleine page) a déjà suffisamment de marge et
-- n'est pas concerné par ce correctif.
local STANDARD_TABLE_WIDTH_TARGET = 0.94

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
    "\\setlength{\\tabcolsep}{\\tablecolsep}",
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
    if is_section_header_row(cells) then
      table.insert(lines, "\\multicolumn{" .. ncols .. "}{c}{" .. cells[1] .. "} \\\\[\\tablerowsep]")
    else
      table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
    end
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
-- Force un saut de COLONNE (pas de page) juste avant le tableau, via
-- \newpage -- PAS \clearpage. Différence cruciale en mode `twocolumn` :
-- \newpage ne fait avancer le flux QUE jusqu'au sommet de la colonne
-- SUIVANTE (celle de droite si on est dans celle de gauche -- sans
-- toucher à la colonne de gauche, qui garde son contenu normal) ; il ne
-- déclenche un vrai saut de PAGE que si on se trouve déjà dans la
-- colonne de droite. \clearpage, à l'inverse, vide systématiquement
-- TOUTE la page (les deux colonnes), même quand seule la colonne
-- courante posait problème -- c'est ce qui laissait une page à moitié
-- vide dans les tests précédents.
--
-- Pourquoi inconditionnel (plus de test \needspace) : `needspace` s'est
-- avéré ne pas fonctionner de façon fiable en mode `twocolumn` natif
-- (\pagegoal/\pagetotal ne sont pas mis à jour de façon fiable avant
-- que le moteur de sortie de page ne se déclenche réellement -- vérifié
-- en isolation, hors de ce document). Un `\newpage` systématique avant
-- CHAQUE tableau .wide reste largement acceptable en coût : dans le pire
-- cas (déjà en colonne de droite), il coûte l'équivalent d'un
-- \clearpage classique ; dans le cas courant (colonne de gauche), il ne
-- coûte RIEN de plus qu'un saut de colonne normal, sans aucun texte
-- perdu. Le tableau démarre alors systématiquement en haut d'une
-- colonne, avec au minimum \textheight de hauteur disponible -- largement
-- suffisant pour n'importe quel tableau .wide raisonnable, ce qui
-- élimine le warning "too tall"/"only floats" sans mesure ni estimation.
--
-- \mbox{} avant \newpage : même précaution que newpage.lua/part_cover.lua
-- face au piège \clearpage/strip de cuted (voir newpage.lua) -- par
-- prudence, appliquée aussi à \newpage au cas où ce tableau .wide
-- suivrait immédiatement un autre tableau/image .wide.
-- Nombre estimé de caractères tenant sur UNE ligne pleine largeur
-- (\textwidth entier, fraction = 1.0) en \tablefontsize (\small).
-- Valeur volontairement PRUDENTE (basse) : elle sous-estime le nombre
-- de caractères par ligne, donc SURESTIME le nombre de lignes -- un
-- \needspace un peu trop généreux (page/colonne tournée un peu tôt)
-- est un défaut bien plus tolérable qu'un \needspace insuffisant
-- (retour du warning "too tall"/"only floats").
local TEXTWIDTH_CHARS_AT_SMALL = 100

-- Estime le nombre de lignes qu'occupera une Row une fois composée,
-- en tenant compte du retour à la ligne DANS CHAQUE CELLULE selon la
-- largeur réelle de sa colonne.
local function estimate_row_lines(row, col_fractions)
  local max_lines = 1
  for i, cell in ipairs(row.cells) do
    local char_count = #blocks_to_plain_text(cell.contents)
    local col_fraction = col_fractions[i] or (1.0 / #row.cells)
    local col_chars = math.max(1, math.floor(col_fraction * TEXTWIDTH_CHARS_AT_SMALL))
    local lines = math.ceil(char_count / col_chars)
    if lines < 1 then lines = 1 end
    if lines > max_lines then max_lines = lines end
  end
  return max_lines
end

-- Compte le nombre total de lignes composées (en-tête + corps, retours
-- à la ligne inclus) d'un Table Pandoc.
local function count_table_rows(tbl)
  local col_fractions = compute_column_widths(tbl, 1.0)
  local total = 0
  for _, row in ipairs(tbl.head.rows) do
    total = total + estimate_row_lines(row, col_fractions)
  end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      total = total + estimate_row_lines(row, col_fractions)
    end
  end
  return total
end

-- Marge de sécurité (en \baselineskip), en plus des lignes de données,
-- pour couvrir la légende, l'espacement \vspace{0.3em}, l'en-tête du
-- tableau et l'espacement avant/après \strip.
local NEEDSPACE_EXTRA_LINES = 6

-- \needspace{N\baselineskip} ne fait RIEN si la page/colonne a assez de
-- place restante (le tableau continue dans le flux normal, sans saut
-- ni espace perdu) ; sinon, il déclenche LUI-MÊME un saut -- vers la
-- colonne suivante s'il en existe une sur la page courante (voir
-- comportement de \newpage en mode twocolumn, décrit plus haut), sinon
-- vers une page neuve. C'est un test CONDITIONNEL : contrairement à un
-- \newpage systématique, il ne coûte RIEN quand le tableau tient déjà
-- (cas des petits tableaux, ex. 3 lignes -- qui ne doivent jamais être
-- poussés inutilement).
--
-- Évalué à l'intérieur d'un groupe {\tablefontsize ...} : \needspace
-- lit \baselineskip au moment de son appel, donc ce groupe garantit que
-- l'estimation utilise l'interligne réel du corps du tableau (\small).
--
-- Nécessite \usepackage{needspace} (voir book/preamble.tex).
local function need_space_latex(tbl)
  local lines = count_table_rows(tbl) + NEEDSPACE_EXTRA_LINES
  return string.format("{\\tablefontsize\\needspace{%d\\baselineskip}}\n", lines)
end

-- Un tableau standalone n'a normalement aucun moyen d'être marqué .wide
-- dans ce document (le flag .wide n'est lu que sur le paragraphe de
-- légende, voir has_wide_flag) -- mais on vérifie tout de même
-- tbl.attr.classes au cas où une vraie syntaxe de légende Pandoc
-- (`: Légende {.wide}`) serait utilisée un jour, ce qui peuple
-- réellement l'Attr du Table lui-même. Dans ce cas, même traitement que
-- captioned_table_wide (strip, pleine largeur), mais sans légende.
local function standalone_table_to_latex(tbl, force_clearpage)
  local wide = tbl.attr and tbl.attr.classes and tbl.attr.classes:includes("wide")

  if wide then
    local tabular = table_to_tabular_lines(tbl, 0.87, "textwidth")
    local body = "\\centering\n\\tablefontsize\n" .. tabular
    -- \mbox{} après \end{strip} -- voir la note détaillée dans
    -- captioned_table_wide plus bas : sans lui, ce tableau perd
    -- SILENCIEUSEMENT tout son contenu s'il se trouve être le dernier
    -- bloc substantiel avant \backmatter/\end{document}.
    -- `force_clearpage` : voir captioned_table_wide -- même règle
    -- d'adjacence à un strip précédent, needspace reste la norme sinon.
    local space_check = force_clearpage and "\\mbox{}\\clearpage\n" or need_space_latex(tbl)
    local latex = space_check .. "\\begin{strip}\n" .. body .. "\n\\end{strip}\n\\mbox{}"
    return pandoc.RawBlock("latex", latex)
  end

  return pandoc.RawBlock("latex", table_to_supertabular_lines(tbl, STANDARD_TABLE_WIDTH_TARGET, "columnwidth"))
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
    table_to_supertabular_lines(tbl, STANDARD_TABLE_WIDTH_TARGET, "columnwidth", caption_latex))
end

-- Tableau AVEC légende préalable, mode pleine largeur (flag .wide).
-- Utilise `strip` (package cuted) plutôt qu'un float table* : le tableau
-- reste exactement à sa place dans le flux (texte 2 colonnes avant/après,
-- tableau pleine largeur entre les deux), sans jamais se déplacer.
-- Légende et tableau sont regroupés dans un seul \begin{strip}...\end{strip}
-- avec \nopagebreak entre les deux, pour qu'ils ne puissent jamais être
-- séparés par une coupure de page.
--
-- `newpage` : soit un flag .newpage explicite sur la légende, soit
-- (voir la fonction Pandoc plus bas) une adjacence détectée avec un
-- strip précédent -- déclenche un \clearpage inconditionnel. En
-- dehors de ces cas, \needspace reste la norme : test conditionnel qui
-- ne coûte AUCUN saut de page inutile pour un tableau isolé qui tient
-- déjà dans la colonne courante.
--
-- ATTENTION -- piège cuted (needspace + strip), à ne traiter QUE dans
-- les cas précis identifiés, pas en systématique (un \clearpage
-- inconditionnel devant chaque tableau .wide a été essayé, mais
-- gaspille une page à chaque petit tableau -- inacceptable) :
--
-- 1. Un strip placé en tout DERNIER bloc du document (rien de
--    substantiel après avant \backmatter/\end{document}) perd tout
--    son contenu : `cuted` reporte la mise en page de `strip` via une
--    routine de sortie modifiée, qui n'est réellement "vidée" qu'au
--    PROCHAIN saut de page déclenché par du contenu normal qui suit.
--    Rien après -> le contenu en attente disparaît, sans la moindre
--    erreur/warning à la compilation. Corrigé par le \mbox{}
--    systématique après CHAQUE \end{strip} (voir plus bas) : coût nul,
--    donc appliqué à tous les strips sans distinction.
-- 2. Un tableau .wide placé juste après un TITRE (Header) qui suit
--    lui-même un strip précédent peut, dans certaines positions de
--    page, faire disparaître CE TITRE (pas le tableau) -- reproduit
--    avec une structure locale identique (titre puis needspace+strip)
--    où seule la variante needspace perdait le titre, jamais un
--    \clearpage inconditionnel au même endroit.
-- 3. Deux tableaux .wide consécutifs, séparés seulement par une ligne
--    vide (aucun titre, aucun texte entre eux) : même symptôme.
--
-- Point commun aux cas 2 et 3 : le strip PRÉCÉDENT vient tout juste de
-- se terminer, avec rien (ou juste un titre) entre les deux -- c'est
-- CETTE adjacence spécifique qui met `cuted` dans un état instable,
-- pas needspace en tant que tel (un tableau .wide isolé, précédé d'un
-- vrai paragraphe, fonctionne très bien avec needspace -- voir le
-- tableau des armes bolts). Le \clearpage n'est donc forcé QUE quand
-- cette adjacence est détectée (voir Pandoc plus bas), jamais pour un
-- tableau .wide "normal".
local function captioned_table_wide(caption_latex, tbl, newpage)
  local tabular = table_to_tabular_lines(tbl, 0.87, "textwidth")
  local body = string.format([[
\centering
{\tablecaptionfontsize %s}\par
\vspace{0.3em}
\nopagebreak
\tablefontsize
%s]], caption_latex, tabular)
  local space_check = newpage and "\\mbox{}\\clearpage\n" or need_space_latex(tbl)
  local latex = space_check .. "\\begin{strip}\n" .. body .. "\n\\end{strip}\n\\mbox{}"
  return pandoc.RawBlock("latex", latex)
end

-- Tableau AVEC légende préalable, mode "grid" : Div MkDocs Material
-- `grid` contenant deux tableaux, affichés côte à côte sous une légende
-- commune. Chaque tableau vise `GRID_TABLE_WIDTH_TARGET` de
-- \columnwidth (marge pour l'espacement entre les deux -- voir
-- ci-dessous pour le détail du budget de largeur).
-- Englobé dans un \begin{samepage}...\end{samepage} : ce bloc reste
-- VOLONTAIREMENT en `tabular` classique (pas de titre "collant" multi-
-- page -- supertabular ne peut pas être imbriqué comme cellule d'un
-- autre tabular, ce qui est la structure même de ce mode). `samepage`
-- empêche LaTeX de couper le bloc en deux entre une page/colonne et la
-- suivante (légende d'un côté, tableaux orphelins de l'autre -- défaut
-- observé avant ce correctif) ; en pratique ces tableaux sont courts
-- (quelques lignes de coûts/valeurs), donc les forcer entiers sur une
-- même colonne/page ne pose pas de problème de place.
--
-- BUDGET DE LARGEUR -- corrige un débordement dans la gouttière entre
-- colonnes de page, constaté en test avec du texte réel des deux
-- côtés (le \tabcolsep par défaut, invisible en soi, s'additionnait à
-- plusieurs endroits sans qu'aucun ne soit budgété) :
--   - Chaque tabular imbriqué (table_to_tabular_lines) a 2 colonnes
--     (Score/Coût ou Score/Modificateur) -- donc 1 seule "jonction"
--     interne, qui ajoute 2x\tabcolsep (12pt par défaut) à la largeur
--     RÉELLE du tableau, EN PLUS de sa largeur de contenu visée
--     (GRID_TABLE_WIDTH_TARGET*\columnwidth). Ce surplus n'était pas
--     budgété. Corrigé en réduisant localement \tabcolsep à
--     \tablegridcolsep (même technique que \monsterblock/\statline
--     dans statblock.lua) pour les DEUX tabulars imbriqués.
--   - Le tabular ENGLOBANT (celui-ci) gardait par défaut son propre
--     \tabcolsep sur ses bords extérieurs (avant la 1re colonne, après
--     la 2e) -- un espace inutile ici (le bloc est déjà centré via
--     \begin{center}), maintenant retiré avec `@{}` aux deux extrémités
--     (même convention que `@{}col_spec@{}` dans table_to_tabular_lines).
-- Le séparateur central (\tablegridsep + filet, voir book/preamble.tex)
-- reste inchangé -- lui EST budgété dès le départ via
-- GRID_TABLE_WIDTH_TARGET (voir sa définition ci-dessous).
local GRID_TABLE_WIDTH_TARGET = 0.42 -- par tableau (au lieu de 0.46) : laisse la marge nécessaire au séparateur central + au \tabcolsep local réduit de chaque tabular imbriqué

local function captioned_table_grid(caption_latex, tbl1, tbl2)
  local tabular1 = table_to_tabular_lines(tbl1, GRID_TABLE_WIDTH_TARGET, "columnwidth", true)
  local tabular2 = table_to_tabular_lines(tbl2, GRID_TABLE_WIDTH_TARGET, "columnwidth", true)
  local latex = string.format([[
\begin{samepage}
\begin{center}
{\tablecaptionfontsize %s}\par
\vspace{0.3em}
\tablefontsize
{\setlength{\tabcolsep}{\tablegridcolsep}%%
\begin{tabular}{@{}c@{\hspace{\tablegridsep}\color{\tablegridrulecolor}\vrule width 0.4pt\hspace{\tablegridsep}}c@{}}
%s & %s
\end{tabular}}%%
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

  -- Vrai juste après avoir émis un strip .wide (tableau, ou --
  -- indirectement -- un bloc monstre .wide déjà résolu en RawBlock par
  -- statblock.lua, qui tourne avant ce filtre). Reste vrai à travers
  -- un ou plusieurs Header consécutifs (un titre ne "sépare" pas
  -- vraiment deux strips aux yeux de cuted, voir le piège documenté
  -- dans captioned_table_wide), mais retombe à faux dès qu'un VRAI
  -- bloc de contenu (paragraphe normal, liste, etc.) s'intercale --
  -- dans ce cas, needspace fonctionne sans problème (confirmé : un
  -- titre isolé, non précédé d'un strip, suivi d'un tableau .wide en
  -- needspace s'affiche correctement).
  local after_wide_strip = false

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
      after_wide_strip = false -- grid = tabular classique, pas un strip

    elseif is_caption_candidate and next_is_table then
      local caption_latex = blocks_to_latex({b})
      local wide = has_wide_flag(b)

      if wide then
        -- ATTENTION -- piège cuted : voir la note détaillée dans
        -- captioned_table_wide. `after_wide_strip` détecte précisément
        -- le cas pathologique (ce tableau arrive juste après un autre
        -- strip, éventuellement séparé par un simple titre) -- SEUL
        -- cas où on force \clearpage ; sinon needspace reste la norme.
        local newpage = has_newpage_flag(b) or after_wide_strip
        table.insert(new_blocks, captioned_table_wide(caption_latex, next_b, newpage))
      else
        table.insert(new_blocks, captioned_table_inline(caption_latex, next_b))
      end
      i = i + 2 -- consomme la légende ET le tableau
      after_wide_strip = wide

    elseif b.t == "Table" then
      local wide = b.attr and b.attr.classes and b.attr.classes:includes("wide")
      table.insert(new_blocks, standalone_table_to_latex(b, after_wide_strip))
      i = i + 1
      after_wide_strip = wide

    elseif b.t == "Header" then
      -- Un titre ne réinitialise PAS after_wide_strip (voir note plus
      -- haut) : on le laisse simplement passer tel quel.
      table.insert(new_blocks, b)
      i = i + 1

    else
      table.insert(new_blocks, b)
      i = i + 1
      after_wide_strip = false
    end
  end

  doc.blocks = new_blocks
  return doc
end
