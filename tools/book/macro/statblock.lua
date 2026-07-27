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

-- Constantes pour l'estimation \needspace d'un bloc monstre .wide (voir
-- fin de la note de render_monster, section LIMITE ASSUMÉE) -- même
-- logique que TEXTWIDTH_CHARS_AT_SMALL / NEEDSPACE_EXTRA_LINES dans
-- tables.lua : volontairement PRUDENTES (basses), pour SURESTIMER le
-- nombre de lignes plutôt que le sous-estimer -- un \needspace un peu
-- trop généreux (saut de colonne/page un peu tôt) est un défaut bien
-- plus tolérable qu'un \needspace insuffisant (retour du cadre qui
-- déborde, voir historique dans Div(el)).
--
-- Deux valeurs séparées car le nombre de caractères qui tiennent sur
-- une ligne dépend de la largeur réellement occupée par le texte :
--   - MONSTER_CHARS_PER_LINE_SPLIT : cas normal (plus d'une section),
--     le contenu est réparti sur 2 \minipage (voir render_monster) --
--     chacune fait à peu près la largeur d'une colonne de document.
--   - MONSTER_CHARS_PER_LINE_FULL : cas rare d'un bloc .wide à une
--     seule section (rien à répartir, voir la branche `else` plus
--     bas) -- le texte occupe alors toute la largeur du cadre, environ
--     le double.
local MONSTER_CHARS_PER_LINE_SPLIT = 55
local MONSTER_CHARS_PER_LINE_FULL = 110

-- Marge de sécurité (en \baselineskip), en plus des lignes de contenu
-- estimées, pour couvrir le nom du monstre, les bordures du cadre
-- (\monsterblock) et les espacements internes.
local MONSTER_NEEDSPACE_EXTRA_LINES = 4

local function estimate_needspace_lines(char_count, chars_per_line)
  return math.ceil(char_count / chars_per_line) + MONSTER_NEEDSPACE_EXTRA_LINES
end

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
-- Div(el) pour comment ce fait est traité (\needspace, PAS un
-- \clearpage systématique -- même logique que les tableaux .wide dans
-- tables.lua). Reste un cas extrême non couvert : un bloc monstre
-- .wide dont le contenu dépasserait la hauteur d'une PAGE ENTIÈRE
-- vierge -- aucune solution avec `strip`/`minipage` dans ce cas
-- (il faudrait alléger le bloc, ou revenir à un vrai float).
--
-- Cette fonction retourne 2 valeurs : le LaTeX du bloc monstre, et (si
-- is_wide) une estimation du nombre de lignes \needspace nécessaires
-- (nil sinon, ou si le bloc ne fait qu'une seule section -- rien à
-- estimer de spécial, voir plus bas).
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
  local needspace_lines = nil

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

    -- La hauteur réellement critique est celle de la colonne la PLUS
    -- LONGUE (l'autre, plus courte, ne pose pas de problème de place).
    needspace_lines = estimate_needspace_lines(
      math.max(left_len, right_len), MONSTER_CHARS_PER_LINE_SPLIT
    )

    table.insert(parts, string.format(
      "\\noindent\\begin{minipage}[t]{0.48\\linewidth}\n%s\n\\end{minipage}\\hfill\n" ..
      "\\begin{minipage}[t]{0.48\\linewidth}\n%s\n\\end{minipage}",
      table.concat(left, "\n\n"), table.concat(right, "\n\n")
    ))
  else
    -- Mode normal (non wide), ou un seul groupe en mode wide (rien à
    -- équilibrer, voir note en tête de fonction) : flux vertical
    -- classique, inchangé par rapport à avant.
    if is_wide then
      local total_len = 0
      for _, rendered in ipairs(rendered_groups) do
        total_len = total_len + #rendered
      end
      needspace_lines = estimate_needspace_lines(total_len, MONSTER_CHARS_PER_LINE_FULL)
    end
    for _, rendered in ipairs(rendered_groups) do
      table.insert(parts, rendered)
    end
  end

  table.insert(parts, "\\end{monsterblock}")
  return table.concat(parts, "\n\n"), needspace_lines
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
  local monster_latex, needspace_lines = render_monster(el, is_wide)

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
  -- Combinable avec .wide sans souci particulier : .wide utilise
  -- désormais \needspace (voir plus bas), un test conditionnel qui ne
  -- coûte rien si la place est déjà suffisante -- si .newcol vient
  -- de caler le flux en haut d'une colonne/page fraîche juste avant,
  -- \needspace constatera simplement qu'il y a assez de place et ne
  -- déclenchera aucun saut supplémentaire (pas de page blanche).
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
  -- \needspace{N\baselineskip}, PAS un \clearpage systématique -- même
  -- logique que les tableaux .wide dans tables.lua (voir need_space_
  -- latex là-bas) : un test CONDITIONNEL, qui ne déclenche un saut de
  -- colonne/page QUE si la place manque réellement. Une tentative
  -- précédente forçait un \clearpage inconditionnel avant tout bloc
  -- .wide -- corrigé ici, pour ne pas gâcher de la place (ni sauter à
  -- une page neuve) quand le bloc tient déjà très bien où il est (cas
  -- Horreur.md, peu de contenu). `needspace_lines` (retourné par
  -- render_monster) estime le nombre de lignes nécessaires à partir de
  -- la colonne la plus longue -- voir sa note pour le détail du calcul
  -- et le pourquoi (rappel du problème observé sans lui : `tcolorbox`
  -- ne peut rien scinder dans nos 2 \minipage, qui sont un bloc
  -- atomique -- si la place manque, le cadre se dessine à une hauteur
  -- erronée et le contenu réel atterrit hors du cadre, plus loin dans
  -- la page).
  --
  -- \mbox{} AVANT \needspace -- ajouté suite à un cas cassé en
  -- pratique (Champion.md, avec un titre {.newpage} juste avant
  -- l'image/intro qui précèdent ce bloc monstre .wide) : rendu
  -- éclaté sur plusieurs pages (bandes de cadre quasi vides, contenu
  -- réel atterrissant 2 pages plus loin, hors cadre). Hypothèse
  -- retenue (non vérifiée par compilation ici, donc à confirmer) :
  -- piège documenté du package needspace lui-même -- juste après un
  -- \clearpage, \pagegoal/\pagetotal ne sont pas encore fiables tant
  -- qu'aucun contenu réel n'a été composé sur la page fraîche ;
  -- \needspace peut alors se tromper sur la place disponible, ce qui,
  -- combiné au caractère atomique de nos 2 \minipage (voir plus haut),
  -- donne ce rendu incohérent. tables.lua ne met pas ce \mbox{} devant
  -- son propre \needspace, mais n'a probablement jamais été exercé
  -- dans cette configuration précise (immédiatement après un titre
  -- .newpage) -- ajouté ici par prudence, par symétrie avec les
  -- autres \mbox{} de ce fichier face aux pièges cuted/page-break.
  -- Coût nul si la page n'a rien de spécial ; à surveiller si le
  -- problème persiste malgré ça (auquel cas il faudrait inspecter le
  -- .tex généré / le log xelatex pour confirmer la cause exacte).
  --
  -- Reste un AUTRE cas d'adjacence non couvert par ce \mbox{} : un bloc
  -- monstre .wide collé JUSTE APRÈS un autre élément .wide (image,
  -- tableau, ou un autre bloc monstre), sans contenu réel entre les
  -- deux -- piège spécifique documenté dans tables.lua sous le nom
  -- `after_wide_strip`, traité là-bas par un \clearpage explicite dans
  -- CE cas précis. Pas répliqué ici pour l'instant ; si ce cas se
  -- présente, préférer .newcol/.newpage en Markdown pour forcer un
  -- calage explicite plutôt que de compter sur \needspace.
  --
  -- `unbreakable` FORCÉ EN LOCAL (\tcbset{monsterblock/.append style=
  -- {unbreakable}}, dans un groupe {...} qui limite l'effet à CE bloc
  -- précis -- les blocs monstre non-wide gardent `breakable` tel que
  -- défini dans preamble.tex) -- ajouté suite à un nouveau cas cassé
  -- observé en pratique (Champion.md, texte d'accompagnement pourtant
  -- allongé) malgré le \mbox{} déjà en place devant \needspace : même
  -- symptôme qu'avant (bandes de cadre vides, contenu réel atterrissant
  -- des pages plus loin, hors cadre). Diagnostic révisé : l'estimation
  -- de \needspace (comptage de caractères, voir MONSTER_CHARS_PER_LINE_*)
  -- est probablement trop imprécise pour du texte de bloc monstre
  -- (paragraphes de longueur variable, contrairement aux lignes de
  -- tableau régulières de tables.lua) -- si elle sous-estime la
  -- hauteur réelle, \needspace conclut à tort qu'il y a assez de place,
  -- et `tcolorbox` (breakable) se retrouve à devoir scinder un contenu
  -- qui reste, de toute façon, atomique (nos 2 \minipage) : IMPOSSIBLE
  -- à couper proprement, d'où le rendu éclaté. En forçant `unbreakable`
  -- ici, tcolorbox n'essaie plus jamais cette coupure impossible -- au
  -- pire (si \needspace se trompe malgré tout), on obtient un simple
  -- débordement (avertissement de compilation), jamais plus ce rendu
  -- incohérent sur plusieurs pages.
  if is_wide then
    local space_check = needspace_lines
      and string.format("\\mbox{}\\needspace{%d\\baselineskip}\n", needspace_lines)
      or ""
    monster_latex = space_check .. "\\begin{strip}\n"
      .. "{\\tcbset{monsterblock/.append style={unbreakable}}\n"
      .. monster_latex .. "\n}"
      .. "\n\\end{strip}\n\\mbox{}"
  end


  return pandoc.RawBlock("latex", monster_latex)
end
