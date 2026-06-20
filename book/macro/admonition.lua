-- Transforme les Div issus des fenced divs Pandoc (::: {.note title="..."} ... :::)
-- en blocs encadrés LaTeX (tcolorbox).
-- Suppose que la syntaxe MkDocs a déjà été convertie en amont par
-- book/scripts/admonition_to_div.py

local colors = {
  note = "blue",
  tip = "green",
  warning = "orange",
  danger = "red",
  info = "blue",
  question = "purple",
}

local titles_fr = {
  note = "Note",
  tip = "Astuce",
  warning = "Attention",
  danger = "Danger",
  info = "Info",
  question = "Question",
}

local function escape_latex(s)
  return s:gsub("([%%&_#{}])", "\\%1")
end

function Div(el)
  for adm_type, color in pairs(colors) do
    if el.classes:includes(adm_type) then
      local title = el.attributes["title"]
      if not title or title == "" then
        title = titles_fr[adm_type] or adm_type
      end

      local before = pandoc.RawBlock("latex",
        string.format(
          "\\begin{tcolorbox}[colback=%s!5!white,colframe=%s!75!black,title={%s},breakable]",
          color, color, escape_latex(title)
        ))
      local after = pandoc.RawBlock("latex", "\\end{tcolorbox}")

      table.insert(el.content, 1, before)
      table.insert(el.content, after)
      return el.content  -- "déballe" le Div, on n'a plus besoin du wrapper
    end
  end
  return el
end
