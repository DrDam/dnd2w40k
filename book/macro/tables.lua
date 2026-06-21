-- Reconstruit les Table Pandoc restantes (hors celles déjà traitées par
-- split_table.lua) en tabular/booktabs, en les attachant à leur légende
-- si une légende (paragraphe en italique, généralement avec l'attribut
-- {.table-title}) la précède immédiatement.
--
-- Style commun à tous les tableaux (voir \newcolumntype L/C/R dans
-- book/preamble.tex) :
--   - colonnes à largeur fixe avec centrage vertical du texte
--   - alignement horizontal sans justification forcée (texte multi-ligne
--     aligné à gauche/droite/centré, jamais étiré bord à bord)
--   - lignes de corps alternées légèrement grisées (gray!12 / white)
--
-- Comportement par défaut : le tableau reste DANS LE FLUX de la colonne
-- courante (pas de float), collé à sa légende -- adapté aux tableaux
-- étroits qui tiennent dans une seule colonne en mode twocolumn.
--
-- Pour les tableaux qui ont VRAIMENT besoin de pleine largeur (plus de
-- colonnes que ne peut en contenir une seule colonne de texte), ajoute
-- le flag .wide sur la légende : *Titre*{.table-title .wide}
-- Dans ce cas, le tableau passe par `strip` (package cuted) : il reste
-- exactement à sa place dans le flux (pas un float qui peut se déplacer).
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

-- Convertit un alignement Pandoc + une largeur (fraction de \textwidth)
-- en spécification de colonne LaTeX, en utilisant les types personnalisés
-- L{}/C{}/R{} (définis dans le préambule via \newcolumntype) qui combinent :
--   - une largeur fixe (permet le retour à la ligne automatique)
--   - un centrage vertical (via m{} sous-jacent)
--   - un alignement horizontal sans justification forcée (\raggedright
--     pour la gauche, \raggedleft pour la droite, \centering pour le centre)
local function align_to_coltype(align, width)
  local letter
  if align == "AlignLeft" then letter = "L"
  elseif align == "AlignRight" then letter = "R"
  elseif align == "AlignCenter" then letter = "C"
  else letter = "L" end
  return string.format("%s{%.4f\\textwidth}", letter, width)
end

-- Calcule une largeur par colonne, en se basant sur les ColWidth fournis
-- par Pandoc quand disponibles (cas des pipe-tables avec séparateurs
-- ajustés), sinon répartition égale. `total_target` contrôle la largeur
-- totale visée (fraction de \textwidth), pour laisser de la marge aux
-- séparateurs entre colonnes et éviter tout débordement.
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

-- Génère le bloc tabular complet (en-tête + corps), avec :
--   - colonnes à largeur fixe et centrage vertical (types L/C/R)
--   - lignes de corps alternées légèrement grisées (\rowcolors)
-- `total_target` : largeur totale visée pour l'ensemble des colonnes
-- (fraction de \textwidth). Utiliser une valeur plus large (~0.98) pour
-- les tableaux en flux normal (une colonne de texte), plus restreinte
-- (~0.87) pour les tableaux pleine largeur (.wide), où il faut plus de
-- marge de sécurité pour éviter tout débordement.
local function table_to_tabular_lines(tbl, total_target)
  local widths = compute_column_widths(tbl, total_target)
  local col_specs = {}
  for idx, colspec in ipairs(tbl.colspecs) do
    table.insert(col_specs, align_to_coltype(tostring(colspec[1]), widths[idx]))
  end
  local col_spec = table.concat(col_specs, "")

  local lines = {
    "\\rowcolors{2}{gray!12}{white}",
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

  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        table.insert(cells, blocks_to_latex(cell.contents))
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
  local tabular = table_to_tabular_lines(tbl, total_target)
  return pandoc.RawBlock("latex",
    "\\begin{" .. env .. "}[!t]\n\\centering\n" .. tabular .. "\n\\end{" .. env .. "}")
end

-- Tableau AVEC légende préalable, mode flux normal (par défaut)
local function captioned_table_inline(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl, 0.98)
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
local function captioned_table_wide(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl, 0.87)
  local latex = string.format([[
\begin{strip}
\centering
%s\par
\vspace{0.3em}
%s
\end{strip}]], caption_latex, tabular)
  return pandoc.RawBlock("latex", latex)
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

    if is_caption_candidate and next_is_table then
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
