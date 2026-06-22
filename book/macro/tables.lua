-- Reconstruit tous les Table Pandoc (tableaux simples ET paires de
-- tableaux MkDocs Material "grid") en tabular/booktabs, en les attachant
-- à leur légende si une légende (paragraphe en italique, généralement
-- avec l'attribut {.table-title}) la précède immédiatement.
--
-- Style commun à tous les tableaux (voir \newcolumntype L/C/R dans
-- book/preamble.tex) :
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
--
-- Trois modes de rendu, suivant la légende qui précède le(s) tableau(x) :
--
--   1. Légende seule + tableau -> mode "standard" : le tableau reste DANS
--      LE FLUX de la colonne courante (pas de float), collé à sa légende.
--      Largeur calée sur \columnwidth (largeur d'UNE colonne de texte en
--      mode twocolumn -- PAS \textwidth, qui vaut la largeur de la PAGE
--      entière et ferait largement déborder le tableau hors de sa
--      colonne).
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
--
--   3. Légende + Div MkDocs Material `grid` contenant DEUX tableaux ->
--      mode "grid" : les deux tableaux s'affichent côte à côte sous une
--      légende commune, chacun avec sa propre largeur calée sur la
--      moitié de \columnwidth.
--
-- Sans légende précédente, le tableau garde l'ancien comportement
-- (choix automatique table/table* selon une heuristique de largeur,
-- en float [!t]), pour ne pas casser les tableaux sans titre.
--
-- Note : nécessaire en mode `twocolumn` car `longtable` (par défaut chez
-- Pandoc) lève une erreur fatale dans ce mode. `tabular` fonctionne
-- toujours, que ce soit dans le flux ou dans un float.

local MAX_NARROW_COLS = 4
local MAX_NARROW_CELL_CHARS = 15

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

local function is_narrow_table(tbl)
  local ncols = #tbl.colspecs
  if ncols > MAX_NARROW_COLS then
    return false
  end
  local function check_rows(rows)
    for _, row in ipairs(rows) do
      for _, cell in ipairs(row.cells) do
        local text = blocks_to_plain_text(cell.contents)
        if #text > MAX_NARROW_CELL_CHARS then
          return false
        end
      end
    end
    return true
  end
  if not check_rows(tbl.head.rows) then return false end
  for _, body in ipairs(tbl.bodies) do
    if not check_rows(body.body) then return false end
  end
  return true
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
    "\\toprule"
  }

  for _, row in ipairs(tbl.head.rows) do
    local cells = {}
    for _, cell in ipairs(row.cells) do
      table.insert(cells, blocks_to_latex(cell.contents))
    end
    table.insert(lines, table.concat(cells, " & ") .. " \\\\")
  end
  table.insert(lines, "\\midrule")

  local body_rows = collect_body_rows(tbl)
  for idx, cells in ipairs(body_rows) do
    local shaded = (idx % 2 == 1)
    if shaded and use_cellcolor then
      local colored_cells = {}
      for _, cell in ipairs(cells) do
        table.insert(colored_cells, "\\cellcolor{gray!12}" .. cell)
      end
      table.insert(lines, table.concat(colored_cells, " & ") .. " \\\\")
    else
      if shaded then
        table.insert(lines, "\\rowcolor{gray!12}")
      end
      table.insert(lines, table.concat(cells, " & ") .. " \\\\")
    end
  end

  table.insert(lines, "\\bottomrule")
  table.insert(lines, "\\end{tabular}")
  return table.concat(lines, "\n")
end

-- Tableau SANS légende préalable : comportement hérité, choix auto table/table* en float
local function standalone_table_to_latex(tbl)
  local narrow = is_narrow_table(tbl)
  local env = narrow and "table" or "table*"
  local total_target = narrow and 0.98 or 0.95
  local width_unit = narrow and "columnwidth" or "textwidth"
  local tabular = table_to_tabular_lines(tbl, total_target, width_unit)
  return pandoc.RawBlock("latex",
    "\\begin{" .. env .. "}[!t]\n\\centering\n" .. tabular .. "\n\\end{" .. env .. "}")
end

-- Tableau AVEC légende préalable, mode flux normal (par défaut).
-- Largeur calée sur \columnwidth : en mode twocolumn, \textwidth est la
-- largeur de la PAGE entière (deux colonnes), alors que ce tableau reste
-- dans une seule colonne -- utiliser \textwidth ici ferait déborder le
-- tableau bien au-delà de sa colonne.
local function captioned_table_inline(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl, 0.98, "columnwidth")
  local latex = string.format([[
\begin{center}
%s\par
\vspace{0.3em}
%s
\end{center}]], caption_latex, tabular)
  return pandoc.RawBlock("latex", latex)
end

-- Tableau AVEC légende préalable, mode pleine largeur (flag .wide).
-- Utilise `strip` (package cuted) plutôt qu'un float table* : le tableau
-- reste exactement à sa place dans le flux (texte 2 colonnes avant/après,
-- tableau pleine largeur entre les deux), sans jamais se déplacer.
-- Légende et tableau sont regroupés dans un seul \begin{strip}...\end{strip}
-- avec \nopagebreak entre les deux, pour qu'ils ne puissent jamais être
-- séparés par une coupure de page.
local function captioned_table_wide(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl, 0.87, "textwidth")
  local latex = string.format([[
\begin{strip}
\centering
%s\par
\vspace{0.3em}
\nopagebreak
%s
\end{strip}]], caption_latex, tabular)
  return pandoc.RawBlock("latex", latex)
end

-- Tableau AVEC légende préalable, mode "grid" : Div MkDocs Material
-- `grid` contenant deux tableaux, affichés côte à côte sous une légende
-- commune. Chaque tableau vise la moitié de \columnwidth (avec marge
-- pour l'espacement entre les deux).
local function captioned_table_grid(caption_latex, tbl1, tbl2)
  local tabular1 = table_to_tabular_lines(tbl1, 0.46, "columnwidth", true)
  local tabular2 = table_to_tabular_lines(tbl2, 0.46, "columnwidth", true)
  local latex = string.format([[
\begin{center}
%s\par
\vspace{0.3em}
\begin{tabular}{cc}
%s & %s
\end{tabular}
\end{center}]], caption_latex, tabular1, tabular2)
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
        table.insert(new_blocks, captioned_table_wide(caption_latex, next_b))
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
