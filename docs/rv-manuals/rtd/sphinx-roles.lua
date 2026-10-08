-- Pandoc Typst reader -> Sphinx RST fixes for the manual.
-- Run with:  pandoc -f typst -t rst --wrap=none --lua-filter=this.lua

local function rst(s) return pandoc.RawInline("rst", s) end

-- A Typst label arrives as Para [Span(id)] right after the block it labels.
local function label_of(b)
  if b and b.t == "Para" and #b.content == 1 and b.content[1].t == "Span"
     and b.content[1].identifier ~= "" and #b.content[1].content == 0 then
    return b.content[1].identifier
  end
end

local function count_images(fig)
  local n = 0
  fig:walk{ Image = function() n = n + 1 end }
  return n
end

local filter = {
  Link = function(el)
    local t = el.target
    if t:sub(1, 4) == "kbd:" then
      local k = t:sub(5):gsub("\\", "\\\\"):gsub("`", "\\`")
      return rst(":kbd:`" .. k .. "`")
    elseif t:sub(1, 5) == "menu:" then
      return rst(":menuselection:`" .. t:sub(6) .. "`")
    elseif t:sub(1, 4) == "ref:" then
      return rst(":ref:`" .. t:sub(5):gsub("^<", ""):gsub(">$", "") .. "`")
    elseif el.classes:includes("ref") and t:sub(1, 1) == "#" then
      return rst(":ref:`" .. t:sub(2) .. "`")
    end
  end,

  -- Typst "it's" after code comes through as a left quote: UTV‘s -> UTV’s
  Str = function(el)
    local fixed = el.text:gsub("(%w)\u{2018}", "%1\u{2019}")
    if fixed ~= el.text then return pandoc.Str(fixed) end
  end,

  -- Shared pixel scale, as in the Typst HTML: one logical pixel (pixels
  -- adjusted for DPI) = one CSS pixel. Relative paths are resolved from the
  -- directory pandoc runs in.
  Image = function(im)
    if im.attributes.width then return nil end
    local f = io.open(im.src, "rb")
    if not f then return nil end
    local data = f:read("a"); f:close()
    local ok, sz = pcall(pandoc.image.size, data)
    if not ok or not sz.width then return nil end
    local dpi = (sz.dpi_horz and sz.dpi_horz > 0) and sz.dpi_horz or 72
    im.attributes.width = string.format("%dpx", math.floor(sz.width * 72 / dpi + 0.5))
    return im
  end,

  -- Multi-image figure: Sphinx's figure holds one image, so use the
  -- multi-figure directive from manual_ext.py (images, then the caption).
  -- Image widths are already set: inline elements are filtered first.
  Figure = function(fig)
    if count_images(fig) <= 1 then return nil end
    local lines = { ".. multi-figure::", "" }
    fig:walk{ Image = function(im)
      table.insert(lines, "   .. image:: " .. im.src)
      if im.attributes.width then
        table.insert(lines, "      :width: " .. im.attributes.width)
      end
      table.insert(lines, "")
    end }
    local cap = pandoc.write(pandoc.Pandoc({ pandoc.Plain(pandoc.utils.blocks_to_inlines(fig.caption.long)) }),
                             "rst", { wrap_text = "none" })
    table.insert(lines, "   " .. cap:gsub("%s+$", ""))
    -- end with a blank line: the writer drops the one after a raw block
    return pandoc.RawBlock("rst", table.concat(lines, "\n") .. "\n\n")
  end,

  -- Replace each label paragraph with an RST target before the labelled
  -- block. Figures and tables are directives, which the writer separates
  -- with a blank line, so a raw target works. Anything else (headings,
  -- caption paragraphs) is rendered together with its target in one raw
  -- block, because the writer drops the blank line after a raw block and
  -- omits header targets that match its auto-generated ids.
  Blocks = function(blocks)
    local out = pandoc.Blocks{}
    for _, b in ipairs(blocks) do
      local id = label_of(b)
      if id and #out > 0 then
        local prev = table.remove(out)
        if prev.t == "Figure" or prev.t == "Table"
           or (prev.t == "RawBlock" and prev.text:match("^%.%. multi%-figure::")) then
          out:insert(pandoc.RawBlock("rst", ".. _" .. id .. ":"))
          out:insert(prev)
        else
          local body = pandoc.write(pandoc.Pandoc({prev}), "rst", {wrap_text = "none"})
          out:insert(pandoc.RawBlock("rst", ".. _" .. id .. ":\n\n" .. body))
        end
      elseif not id then
        out:insert(b)
      end
    end
    return out
  end,
}

return filter
