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

      -- `enhanced,breakable` (même combinaison que \monsterblock, voir
      -- preamble.tex) : autorise tcolorbox à couper la boîte sur la
      -- colonne/page suivante si son contenu est trop long pour tenir
      -- d'une seule pièce -- comportement standard de tcolorbox une
      -- fois `breakable` activé (bordure/fond redessinés proprement de
      -- part et d'autre de la coupure, titre non répété par défaut).
      -- Remplace l'ancien \begin{samepage}...\end{samepage}, qui
      -- interdisait justement toute coupure (samepage = "refuse un
      -- saut de page à l'intérieur de ce bloc"), forçant l'admonition
      -- à déborder silencieusement si elle dépassait la hauteur
      -- restante de la colonne.
      local before = pandoc.RawBlock("latex",
        string.format(
          "\\begin{tcolorbox}[enhanced,breakable,colback=%s!5!white,colframe=%s!75!black,title={%s},before upper={\\setlength{\\parskip}{6pt}}]",
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
