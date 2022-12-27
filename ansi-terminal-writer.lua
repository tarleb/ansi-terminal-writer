--- Pandoc writer for ANSI terminals.
-- This writer uses new features added in pandoc 3, including writer
-- scaffolding and custom writer extensions.
PANDOC_VERSION:must_be_at_least '3.0'

local unpack = unpack or table.unpack
local format = string.format
local layout = pandoc.layout
local empty, cr, concat, blankline, space =
  layout.empty, layout.cr, layout.concat, layout.blankline, layout.space
local cblock, rblock, prefixed, nest, hang =
  layout.cblock, layout.rblock, layout.prefixed, layout.nest, layout.hang
local to_roman = pandoc.utils.to_roman_numeral
local stringify = pandoc.utils.stringify
local List = pandoc.List

local footnotes = List{}

local format_number = {
  Decimal      = function (n) return format("%d", n) end,
  Example      = function (n) return format("%d", n) end,
  DefaultStyle = function (n) return format("%d", n) end,
  LowerAlpha   = function (n) return string.char(96 + (n % 26)) end,
  UpperAlpha   = function (n) return string.char(64 + (n % 26)) end,
  UpperRoman   = function (n) return to_roman(n) end,
  LowerRoman   = function (n) return to_roman(n):lower() end,
}

local list_elements = List{'BulletList', 'OrderedList', 'DefinitionList'}
local function is_tight_list(list)
  if not list_elements:includes(list.tag) then
    return false
  end
  for i, item in ipairs(list.content) do
    if not (#item == 1 and item[1].tag == "Plain") and
       not (#item == 2 and item[1].tag == "Plain" and
            list_elements:includes(item[2].tag)) then
      return false
    end
  end
  return true
end

local unicode_superscript = {
  ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴',
  ['5'] = '⁵', ['6'] = '⁶', ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹',
  ['+'] = '⁺', ['-'] = '⁻', ['='] = '⁼', ['('] = '⁽', [')'] = '⁾',
}

local font_effects = setmetatable(
  {
    bold       = {'1', '22'},
    faint      = {'2', '22'},
    italic     = {'3', '23'},
    underline  = {'4', '24'},
    underlined = {'4', '24'},
    blink      = {'5', '25'},
    inverse    = {'7', '27'},
    strikeout  = {'9', '29'},
  },
  {
    __index = function (_, key)
     error('Unknown font effect ' .. tostring(key))
    end
  }
)
local function font (effects, b)
  effects = type(effects) == 'table' and effects or {effects}
  local start_codes, stop_codes = List{}, List{}
  for _, effect in ipairs(effects) do
    local start, stop = unpack(font_effects[effect])
    start_codes:insert(start)
    stop_codes:insert(stop)
  end
  return concat{
    format('\027[%sm', table.concat(start_codes, ';')),
    b,
    format('\027[%sm', table.concat(stop_codes, ';')),
  }
end

--- Supported writer extensions
Extensions = {
  italic = false,
  unicode = false,
}

Writer = pandoc.scaffolding.Writer

local inlines = Writer.Inlines
local blocks = Writer.Blocks

Writer.Pandoc = function (doc, opts)
  local d = blocks(doc.blocks, blankline)
  local notes = footnotes:map(function (note, i)
      local prefix = opts.extensions:includes 'unicode'
        and tostring(i):gsub('.', unicode_superscript) .. space
        or concat{format("[^%d]:", i), space}
      return hang(blocks(footnotes[i], blankline), 4, prefix)
  end)
  return {d, blankline, concat(notes, blankline)}
end

Writer.Block.Para = function(el)
  return inlines(el.content)
end

Writer.Block.Plain = function(el)
  return inlines(el.content)
end

Writer.Block.BlockQuote = function(el)
  return prefixed(nest(blocks(el.content, blankline), 1), ">")
end

Writer.Block.Header = function(h, opts)
  local texts
  if h.level <= 1 then
    return cblock(
      font({'bold', 'underline'}, inlines(h.content)),
      opts.columns
    )
  elseif h.level <= 2 then
    return cblock(
      font({'bold'}, inlines(h.content)),
      opts.columns
    )
  elseif h.level <= 3 then
    return font({'bold', 'underline'}, inlines(h.content))
  elseif h.level <= 4 then
    return font('faint', inlines(h.content))
  else
    return font('bold', inlines(h.content))
  end
end

Writer.Block.Div = function(el)
  return {cr, blocks(el.content, blankline), blankline}
end

Writer.Block.RawBlock = function(el)
  return empty
end

Writer.Block.Null = function(el)
  return empty
end

Writer.Block.LineBlock = function(el)
  return concat(el.content:map(inlines), cr)
end

Writer.Block.Table = function(el)
  return 'table omitted'
end

Writer.Block.DefinitionList = function(el)
  local function render_def (def)
    return concat{blankline, blocks(def), blankline}
  end
  local function render_item(item)
    local term, defs = unpack(item)
    local inner = concat(defs:map(render_def))
    return hang(inner, 2, concat{ inlines{pandoc.Strong(term)}, cr })
  end
  return concat(el.content:map(render_item), blankline)
end

Writer.Block.BulletList = function(ul)
  local function render_item (item)
    return hang(blocks(item, blankline), 2, "- ")
  end
  local sep = is_tight_list(ul) and cr or blankline
  return cr .. concat(ul.content:map(render_item), sep)
end

Writer.Block.OrderedList = function(ol)
  local result = List{cr}
  local num = ol.start
  local maxnum = num + #ol.content
  local width =
    (maxnum > 9 and 4) or
    (List{'UpperRoman', 'LowerRoman'}:includes(ol.style) and 5) or
    3
  local delimfmt =
    (ol.delimiter == pandoc.OneParen and "%s)") or
    (ol.delimiter == pandoc.TwoParens and "(%s)") or
    "%s."
  local num_formatter = format_number[ol.style]
  for i, item in ipairs(ol.content) do
    local barenum = num_formatter(num)
    local numstr = format(delimfmt, barenum)
    local sps = width - #numstr
    local numsp = (sps < 1) and space or string.rep(" ", sps)
    result:insert(
      hang(blocks(ol.content[i], blankline), width, concat{numstr,numsp})
    )
    num = num + 1
  end
  local sep = is_tight_list(ol) and cr or blankline
  return concat(result, sep)
end

Writer.Block.CodeBlock = function(cb)
  return nest(concat { cr, cb.text, cr }, 4)
end

Writer.Block.HorizontalRule = function(_, opts)
  return cblock("* * * * *", opts.columns)
end

Writer.Inline.Str = function(el)
  return el.text
end

Writer.Inline.Space = space

Writer.Inline.SoftBreak = function(el, opts)
  return opts.wrap_text == "wrap-preserve" and cr or space
end

Writer.Inline.LineBreak = cr

Writer.Inline.RawInline = function()
  return empty
end

Writer.Inline.Code = function(code)
  return font('bold', code.text)
end

Writer.Inline.Emph = function(em, opts)
  return opts.extensions:includes 'italic'
    and font('italic', inlines(em.content))
    or font('underline', inlines(em.content))
end

Writer.Inline.Strong = function(el)
  return font('bold', inlines(el.content))
end

Writer.Inline.Strikeout = function(el)
  return font('strikeout', inlines(el.content))
end

Writer.Inline.Subscript = function(el)
  return { '~', inlines(el.content), '~'}
end

Writer.Inline.Superscript = function(el)
  return { '^', inlines(el.content), '^'}
end

Writer.Inline.SmallCaps = function(el)
  local function to_upper (str)
    return pandoc.text.upper(str.text)
  end
  return inlines(el.content:walk {Str = to_upper})
end

Writer.Inline.Underline = function(u)
  return font('underline', inlines(u.content))
end

Writer.Inline.Cite = function(el)
  return inlines(el.content)
end

Writer.Inline.Math = function(el)
  local marker = el.mathtype == 'DisplayMath' and '$$' or '$'
  return { marker, Inline.Code(el) }
end

Writer.Inline.Span = function(span)
  return inlines(span.content)
end

Writer.Inline.Link = function(link)
  if link.target:match '^%#' then
    -- drop internal links
    return inlines(link.content)
  elseif link.target == stringify(link.content) then
    -- drop autolinks
    return inlines(link.content)
  else
    return inlines(link.content .. {pandoc.Note(pandoc.Plain{link.target})})
  end
end

Writer.Inline.Image = function(el)
  return inlines(el.caption)
end

Writer.Inline.Quoted = function(q)
  return q.quotetype == pandoc.DoubleQuote
    and inlines(q.content):double_quotes()
    or  inlines(q.content):quotes()
end

Writer.Inline.Note = function(note, opts)
  footnotes:insert(note.content)
  local num = #footnotes
  return opts.extensions:includes 'unicode'
    and tostring(num):gsub('[%d]', unicode_superscript)
    or format("[^%d]", num)
end
