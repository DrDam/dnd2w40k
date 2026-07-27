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
      table.insert(cells, "\\textbf{" .. inlines_to_latex(pandoc.utils.blocks_to_inlines(cell.contents)) .. "}")
    end
    table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
  end

  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do
      local cells = {}
      for _, cell in ipairs(row.cells) do
        table.insert(cells, inlines_to_latex(pandoc.utils.blocks_to_inlines(cell.contents)))
      end
      table.insert(lines, table.concat(cells, " & ") .. " \\\\[\\tablerowsep]")
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

-- Note : ce fichier a précédemment expérimenté une estimation
-- \needspace{N\baselineskip} (N calculé à partir d'un comptage de
-- caractères) pour éviter un \clearpage systématique avant les blocs
-- monstre .wide. Abandonné -- voir la note complète dans Div(el),
-- juste avant l'ouverture du \begin{strip} : l'estimation s'est
-- révélée capable de sous-estimer la hauteur réelle nécessaire, ce qui
-- a entraîné une PERTE SILENCIEUSE DE CONTENU (pas juste un débordement
-- visuel) sur un cas réel -- `strip` (cuted) ne pouvant pas continuer
-- sur la page suivante. render_monster ne calcule donc plus rien de ce
-- genre ; Div(el) force systématiquement un \clearpage à la place.

-- Construit le LaTeX complet d'un Div .monster : parcourt son contenu
-- au premier niveau (Header, Div .statline, Para, HorizontalRule...),
-- regroupe les blocs par section (voir render_section), délègue
-- chaque type de bloc au bon renderer, et assemble le tout en une
-- seule chaîne, encadrée par \begin{monsterblock}...\end{monsterblock}.
--
-- is_wide (bool) : si vrai, le CONTENU du cadre (nom, stats, sections)
-- est réparti sur 2 colonnes, EN PLUS du cadre lui-même qui passe en
-- pleine largeur de page (voir Div(el), qui ouvre le \begin{strip}
-- correspondant autour du résultat de cette fonction). Les deux
-- mécanismes sont bien distincts :
--   - .wide (Div(el))       -> le CADRE occupe toute la largeur de
--                              page au lieu d'une colonne du document.
--   - is_wide (ici)         -> à L'INTÉRIEUR de ce cadre élargi, le
--                              texte est réparti sur 2 colonnes plutôt
--                              que d'être composé en lignes très
--                              longues sur toute cette largeur.
--
-- POURQUOI DEUX \minipage CÔTE À CÔTE, ET PAS \begin{multicols}{2}
-- (tentative initiale, abandonnée) -- `tcolorbox` en mode `breakable`
-- (\monsterblock, preamble.tex) N'EST PAS COMPATIBLE avec `multicols`
-- imbriqué à l'intérieur : constaté en test, le cadre (fond + bordure)
-- ne s'étire pas sur la hauteur réelle du contenu -- son calcul de
-- hauteur se base sur un flux vertical classique, alors que multicols
-- répartit son contenu via \vsplit (mécanisme de bas niveau, invisible
-- du calcul de hauteur de tcolorbox) -- résultat observé : la colonne
-- la plus longue (ex: la section "Actions") déborde hors du cadre, et
-- le \begin{samepage}...\end{samepage} de render_section n'est plus
-- respecté non plus (une section peut alors se retrouver coupée en
-- deux, son titre dans une colonne et son corps dans l'autre).
--
-- Solution retenue : un découpage MANUEL, décidé ICI en Lua plutôt que
-- délégué à un mécanisme LaTeX automatique -- chaque section (déjà
-- rendue par render_section, donc déjà un bloc \samepage intact et
-- indivisible) est assignée EN ENTIER à la colonne de gauche ou de
-- droite, jamais scindée. Pas de conflit possible avec tcolorbox
-- (une \minipage est un simple bloc de contenu, pas un mécanisme de
-- pagination comme multicols), et plus aucun risque qu'une section
-- soit coupée en deux entre les colonnes.
--
-- Équilibrage : voir la boucle "greedy" dans render_monster -- à
-- défaut de connaître la hauteur réelle de chaque section sans
-- compiler (ce que ferait \vsplit, mais qu'on a justement écarté),
-- on utilise la longueur du LaTeX généré comme proxy approximatif de
-- la hauteur, et on assigne chaque section à la colonne actuellement
-- la plus courte -- résultat raisonnablement équilibré en pratique,
-- sans garantie d'équilibre parfait (compromis assumé, comme pour
-- STATLINE_WIDTH_TARGET ou le \tabcolsep plus haut dans ce fichier).
--
-- LIMITE ASSUMÉE -- pagination : .wide s'appuie sur `strip` (cuted),
-- qui n'est pas prévu pour franchir une limite de page. Une \minipage
-- ne se coupe jamais non plus entre deux pages. Une \minipage (les 2
-- côte à côte) étant un bloc ATOMIQUE et INSÉCABLE, `breakable`
-- (tcolorbox, préambule) ne peut de toute façon rien y scinder : voir
-- Div(el) pour comment ce fait est traité (\clearpage systématique +
-- `unbreakable` forcé localement -- PAS \needspace, voir l'historique
-- dans Div(el) : une estimation par comptage de caractères s'est
-- révélée capable de sous-estimer la hauteur réelle, entraînant une
-- perte SILENCIEUSE de contenu, `strip` ne pouvant pas continuer sur
-- la page suivante). Reste un cas extrême non couvert : un bloc
-- monstre .wide dont le contenu dépasserait la hauteur d'une PAGE
-- ENTIÈRE vierge -- aucune solution avec `strip`/`minipage` dans ce
-- cas (il faudrait alléger le bloc, ou revenir à un vrai float).
--
-- Cette fonction retourne le LaTeX complet du bloc monstre (chaîne).
local function render_monster(div, is_wide)
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

  -- Rendu de chaque section indépendamment -- nécessaire ici (et pas
  -- seulement au moment de l'assemblage final) car en mode is_wide on
  -- a besoin de la longueur de chaque section déjà rendue pour
  -- l'équilibrage gauche/droite (voir note en tête de fonction).
  local rendered_groups = {}
  for _, group in ipairs(groups) do
    table.insert(rendered_groups, render_section(group, name_level))
  end

  local parts = {"\\begin{monsterblock}"}

  if is_wide and #rendered_groups > 1 then
    -- Équilibrage "greedy" par longueur de LaTeX généré (proxy de la
    -- hauteur, voir note en tête de fonction) : chaque section, dans
    -- son ordre d'origine, est assignée EN ENTIER à la colonne
    -- actuellement la plus courte. Une section ne peut donc jamais se
    -- retrouver scindée entre les deux colonnes.
    local left, right = {}, {}
    local left_len, right_len = 0, 0
    for _, rendered in ipairs(rendered_groups) do
      if left_len <= right_len then
        table.insert(left, rendered)
        left_len = left_len + #rendered
      else
        table.insert(right, rendered)
        right_len = right_len + #rendered
      end
    end

    table.insert(parts, string.format(
      "\\noindent\\begin{minipage}[t]{0.48\\linewidth}\n%s\n\\end{minipage}\\hfill\n" ..
      "\\begin{minipage}[t]{0.48\\linewidth}\n%s\n\\end{minipage}",
      table.concat(left, "\n\n"), table.concat(right, "\n\n")
    ))
  else
    -- Mode normal (non wide), ou un seul groupe en mode wide (rien à
    -- équilibrer, voir note en tête de fonction) : flux vertical
    -- classique, inchangé par rapport à avant.
    for _, rendered in ipairs(rendered_groups) do
      table.insert(parts, rendered)
    end
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
  local is_wide = el.classes:includes("wide")
  local monster_latex = render_monster(el, is_wide)

  -- Bloc monstre .newcol : force un changement de COLONNE (jamais de
  -- page) juste avant le bloc, même logique que .newpage
  -- (newpage.lua) mais avec \newpage au lieu de \clearpage. Le
  -- document compilant en documentclass: book, option twocolumn
  -- (voir metadata.yaml / note en tête de ce fichier sur .statline),
  -- \newpage y a un comportement différent de \clearpage : il clôt la
  -- colonne courante et repart en haut de la colonne suivante -- s'il
  -- reste de la place sur la même page, seule la colonne change, pas
  -- la page ; s'il n'y a plus de colonne libre sur la page, LaTeX
  -- passe alors naturellement à la page suivante. \clearpage, lui,
  -- force TOUJOURS une nouvelle page (et vide les flottants en
  -- attente), ce qui n'est pas ce qu'on veut ici pour un simple calage
  -- de colonne.
  --
  -- \mbox{} devant : même précaution que newpage.lua face au piège
  -- \clearpage/\newpage après un \end{strip} laissé par cuted
  -- (tables.lua / wide_image.lua pour les tableaux/images .wide) --
  -- voir newpage.lua pour le détail complet du mécanisme.
  --
  -- À ÉVITER en combinaison avec .wide sur le même bloc : .wide force
  -- désormais à nouveau son propre \clearpage systématique (voir plus
  -- bas). Combiner .newcol ET .wide produirait donc \newpage (change de
  -- colonne/page) immédiatement suivi d'un \clearpage -- au mieux
  -- redondant, au pire une page blanche si le \newpage venait de
  -- suffire à lui seul. Les deux classes n'ont normalement pas besoin
  -- d'être combinées (.wide garantit déjà à lui seul un début de page
  -- frais).
  if el.classes:includes("newcol") then
    monster_latex = "\\mbox{}\\newpage\n" .. monster_latex
  end

  -- Bloc monstre .wide : pleine largeur de PAGE plutôt que pleine
  -- largeur de COLONNE (comportement par défaut). Réutilise le même
  -- mécanisme que les images .wide (wide_image.lua) et les tableaux
  -- .wide (tables.lua) : l'environnement `strip` du package cuted,
  -- qui étale son contenu sur toute la largeur de la page à sa place
  -- exacte dans le flux, sans devenir un float susceptible de se
  -- déplacer. Le tcolorbox \monsterblock se redimensionne tout seul
  -- (il est défini en \linewidth, qui vaut alors la largeur de page
  -- complète à l'intérieur de strip) -- aucun changement requis côté
  -- preamble.tex pour ce cas. `monster_latex` contient déjà, à ce
  -- stade, le découpage en 2 \minipage construit par render_monster
  -- (voir sa note pour le détail de la répartition en 2 colonnes DANS
  -- ce cadre élargi) -- ce bloc ne fait qu'ouvrir la pleine largeur de
  -- PAGE autour, il ne touche pas au colonnage interne.
  --
  -- `unbreakable` FORCÉ EN LOCAL (\tcbset{monsterblock/.append style=
  -- {unbreakable}}, dans un groupe {...} qui limite l'effet à CE bloc
  -- précis -- les blocs monstre non-wide gardent `breakable` tel que
  -- défini dans preamble.tex) : `tcolorbox` (breakable) ne peut de
  -- toute façon rien scinder dans nos 2 \minipage (bloc atomique) --
  -- autant lui dire explicitement de ne plus essayer.
  --
  -- \clearpage SYSTÉMATIQUE (retour en arrière assumé -- voir plus bas
  -- pourquoi) : garantit que le bloc démarre TOUJOURS en haut d'une
  -- page fraîche, avec le MAXIMUM de hauteur disponible.
  --
  -- HISTORIQUE -- pourquoi ce n'est plus \needspace : une itération
  -- précédente utilisait \needspace{N\baselineskip} (N estimé à partir
  -- d'un comptage de caractères, voir MONSTER_CHARS_PER_LINE_* plus
  -- haut), pour éviter de gâcher de la place quand le bloc tenait déjà
  -- bien où il était -- cohérent avec l'approche de tables.lua pour
  -- les tableaux .wide. Mais un test réel (Champion.md, avec un texte
  -- d'accompagnement plus long) a révélé un problème BEAUCOUP plus
  -- grave qu'un simple débordement visuel : quand l'estimation
  -- sous-estime la hauteur réelle nécessaire, \needspace conclut à
  -- tort qu'il reste assez de place, le cadre s'ouvre alors qu'il ne
  -- reste PAS assez de hauteur sur la page -- et comme `strip` (cuted)
  -- ne peut PAS continuer sur la page suivante (voir la limite déjà
  -- documentée plus haut), tout ce qui dépasse la hauteur restante est
  -- SILENCIEUSEMENT PERDU, pas juste mal affiché : constaté en
  -- pratique, la moitié des Traits, tous les Actions et la Réaction du
  -- Champion du Chaos avaient purement et simplement disparu du PDF
  -- généré, sans la moindre erreur de compilation.
  --
  -- Contrairement à un tableau (tables.lua, contenu très régulier :
  -- une ligne = une hauteur prévisible), un bloc monstre est fait de
  -- paragraphes de longueur variable -- une estimation par comptage de
  -- caractères y est structurellement moins fiable. Le risque de perte
  -- de contenu étant largement pire qu'un peu de place gâchée, le
  -- compromis n'est plus jugé acceptable ici : on revient donc à un
  -- \clearpage inconditionnel, qui maximise la marge de sécurité à
  -- chaque fois plutôt que de la calculer (mal) au cas par cas.
  --
  -- LIMITE RÉSIDUELLE, non éliminée par ce \clearpage : si le contenu
  -- d'un bloc monstre .wide dépasse à lui seul la hauteur d'une PAGE
  -- ENTIÈRE vierge, le même risque de perte silencieuse resterait
  -- théoriquement possible (`strip` ne saurait toujours pas continuer
  -- sur une page suivante). `unbreakable` (ci-dessus) transforme au
  -- moins ce cas en dépassement visible (avertissement de compilation)
  -- plutôt qu'en perte totalement silencieuse -- mais si un bloc
  -- monstre s'avère un jour aussi long, il faudrait revoir l'approche
  -- (alléger le contenu, ou changer de mécanisme que `strip`).
  --
  -- \mbox{} avant \clearpage : même précaution que newpage.lua et
  -- part_cover.lua face au piège \clearpage/strip de cuted (voir
  -- newpage.lua pour le détail) -- au cas où ce bloc monstre .wide
  -- suivrait immédiatement un autre tableau/image .wide.
  if is_wide then
    monster_latex = "\\mbox{}\\clearpage\n\\begin{strip}\n"
      .. "{\\tcbset{monsterblock/.append style={unbreakable}}\n"
      .. monster_latex .. "\n}"
      .. "\n\\end{strip}\n\\mbox{}"
  end


  return pandoc.RawBlock("latex", monster_latex)
end
