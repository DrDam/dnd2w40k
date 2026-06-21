-- Reconstruit TOUTES les Table Pandoc restantes (hors celles déjà traitées
-- par grid.lua) en tabular/booktabs, en choisissant automatiquement entre :
--   - `table` (une seule colonne, float [!t]) pour les tableaux étroits
--   - `table*` (pleine largeur, float [!t]) pour les tableaux larges

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
  return s
end

local function blocks_to_plain_text(blocks)
  local doc = pandoc.Pandoc(blocks)
  return pandoc.utils.stringify(doc)
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

local function table_to_latex(tbl)
  local narrow = is_narrow_table(tbl)
  local env = narrow and "table" or "table*"
  local aligns = {}
  for _, colspec in ipairs(tbl.colspecs) do
    table.insert(aligns, align_to_latex(tostring(colspec[1])))
  end
  local col_spec = table.concat(aligns, "")
  local lines = {"\\begin{" .. env .. "}[!t]", "\\centering", "\\begin{tabular}{@{}" .. col_spec .. "@{}}", "\\toprule"}
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
  table.insert(lines, "\\end{" .. env .. "}")
  return pandoc.RawBlock("latex", table.concat(lines, "\n"))
end

function Table(tbl)
  return table_to_latex(tbl)
end
