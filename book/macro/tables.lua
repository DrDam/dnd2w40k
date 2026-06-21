-- Reconstruit les Table Pandoc restantes (hors celles déjà traitées par
-- split_table.lua) en tabular/booktabs, en les attachant à leur légende
-- si une légende (paragraphe en italique, généralement avec l'attribut
-- {.table-title}) la précède immédiatement.
--
-- Comportement par défaut : le tableau reste DANS LE FLUX de la colonne
-- courante (pas de float), collé à sa légende.
--
-- Flag .wide sur la légende (*Titre*{.table-title .wide}) : passe en
-- table*[!t] (float pleine largeur) pour les tableaux trop larges pour
-- une seule colonne.
--
-- Sans légende précédente : comportement hérité (choix auto table/table*
-- en float, selon largeur estimée).

local MAX_NARROW_COLS = 4
local MAX_NARROW_CELL_CHARS = 15

local function align_to_latex(align)
  if align == "AlignLeft" then return "l"
  elseif align == "AlignRight" then return "r"
  elseif align == "AlignCenter" then return "c"
  else return "l" end
end

local function blocks_to_latex(blocks)
  local doc = pandoc.Pandoc(blocks)
  local s = pandoc.write(doc, "latex")
  s = s:gsub("\n", " ")
  s = s:gsub("%s+$", "")
  s = s:gsub("%s*\\%{%.[%a%-%s\"=.]*\\%}%s*$", "")
  return s
end

local function blocks_to_plain_text(blocks)
  local doc = pandoc.Pandoc(blocks)
  return pandoc.utils.stringify(doc)
end

local function has_wide_flag(block)
  local text = blocks_to_plain_text({block})
  return text:find("%.wide") ~= nil
end

local function is_narrow_table(tbl)
  local ncols = #tbl.colspecs
  if ncols > MAX_NARROW_COLS then return false end
  local function check_rows(rows)
    for _, row in ipairs(rows) do
      for _, cell in ipairs(row.cells) do
        local text = blocks_to_plain_text(cell.contents)
        if #text > MAX_NARROW_CELL_CHARS then return false end
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

local function table_to_tabular_lines(tbl)
  local aligns = {}
  for _, colspec in ipairs(tbl.colspecs) do
    table.insert(aligns, align_to_latex(tostring(colspec[1])))
  end
  local col_spec = table.concat(aligns, "")
  local lines = {"\\begin{tabular}{@{}" .. col_spec .. "@{}}", "\\toprule"}
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

local function standalone_table_to_latex(tbl)
  local narrow = is_narrow_table(tbl)
  local env = narrow and "table" or "table*"
  local tabular = table_to_tabular_lines(tbl)
  return pandoc.RawBlock("latex",
    "\\begin{" .. env .. "}[!t]\n\\centering\n" .. tabular .. "\n\\end{" .. env .. "}")
end

local function captioned_table_inline(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl)
  local latex = string.format([[
\begin{center}
%s\par
\vspace{0.3em}
%s
\end{center}]], caption_latex, tabular)
  return pandoc.RawBlock("latex", latex)
end

local function captioned_table_wide(caption_latex, tbl)
  local tabular = table_to_tabular_lines(tbl)
  local latex = string.format([[
\begin{table*}[!t]
\centering
\caption*{%s}
%s
\end{table*}]], caption_latex, tabular)
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
      i = i + 2
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
