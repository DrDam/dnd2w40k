-- Transforme une légende suivie d'un Div MkDocs Material grid contenant
-- DEUX tableaux, en un tableau LaTeX splitté côte à côte avec légende
-- commune au-dessus.

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
  -- Nettoie les résidus d'attributs Markdown non interprétés par Pandoc
  -- (ex: {.table-title} laissé tel quel côté texte, utile pour le style
  -- CSS côté MkDocs Material mais sans signification pour Pandoc/LaTeX).
  -- Les accolades sont échappées par pandoc.write (\{ \}), donc on les cible ainsi.
  s = s:gsub("%s*\\%{%.[%a%-%s\"=]*\\%}%s*$", "")
  return s
end
local function table_to_tabular(tbl)
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
    local next_is_grid_pair = next_b and next_b.t == "Div"
      and next_b.classes:includes("grid")
      and grid_is_two_tables(next_b)
    if is_caption_candidate and next_is_grid_pair then
      local caption_latex = blocks_to_latex({b})
      local tab1 = table_to_tabular(next_b.content[1])
      local tab2 = table_to_tabular(next_b.content[2])
      local latex = string.format([[
\begin{center}
%s\par
\vspace{0.3em}
\begin{tabular}{cc}
%s & %s
\end{tabular}
\end{center}]], caption_latex, tab1, tab2)
      table.insert(new_blocks, pandoc.RawBlock("latex", latex))
      i = i + 2
    else
      table.insert(new_blocks, b)
      i = i + 1
    end
  end
  doc.blocks = new_blocks
  return doc
end
