-- keep-together.lua — Prevent tables and code blocks from splitting across pages.
--
-- Problem: LaTeX longtables and code blocks (ASCII wire-format diagrams)
-- break across pages, and bold title paragraphs that label them can end up
-- orphaned on the previous page.
--
-- Fix:
--   Tables:      \needspace estimated from row count keeps the table (or at
--                least its first chunk) on one page.  \nopagebreak after a
--                bold title paragraph glues the label to the table.
--   Code blocks: Short blocks (≤ 30 lines) are wrapped in a minipage so
--                they cannot split.  A bold title preceding the block is
--                included inside the minipage.

local function table_row_count(tbl)
  local count = #tbl.head.rows
  for _, body in ipairs(tbl.bodies) do
    count = count + #body.body
  end
  return count
end

local function code_block_lines(blk)
  local count = 1
  for _ in blk.text:gmatch("\n") do
    count = count + 1
  end
  return count
end

-- A "title paragraph" starts with Strong (bold) text — matches patterns
-- like **Data Unit Summary** or **Payload:** that label tables / diagrams.
local function is_title_paragraph(blk)
  if blk.t ~= "Para" then return false end
  if #blk.content == 0 then return false end
  return blk.content[1].t == "Strong"
end

function Blocks(blocks)
  local new = pandoc.List()
  local i = 1

  while i <= #blocks do
    local blk = blocks[i]
    local next_blk = blocks[i + 1]

    -- Bold title followed by Table: needspace + nopagebreak
    if is_title_paragraph(blk) and next_blk and next_blk.t == "Table" then
      local rows = table_row_count(next_blk)
      local cm = math.max(4, (rows + 3) * 0.7)
      new:insert(pandoc.RawBlock("latex",
        string.format("\\needspace{%.1fcm}", cm)))
      new:insert(blk)
      new:insert(pandoc.RawBlock("latex", "\\nopagebreak"))
      new:insert(next_blk)
      i = i + 2

    -- Bold title followed by CodeBlock: minipage around both (if short)
    elseif is_title_paragraph(blk) and next_blk and next_blk.t == "CodeBlock" then
      local lines = code_block_lines(next_blk)
      if lines <= 30 then
        local cm = math.max(3, (lines + 4) * 0.5)
        new:insert(pandoc.RawBlock("latex",
          string.format("\\needspace{%.1fcm}\n\\begin{minipage}{\\linewidth}", cm)))
        new:insert(blk)
        new:insert(next_blk)
        new:insert(pandoc.RawBlock("latex", "\\end{minipage}"))
      else
        new:insert(pandoc.RawBlock("latex", "\\needspace{5cm}"))
        new:insert(blk)
        new:insert(pandoc.RawBlock("latex", "\\nopagebreak"))
        new:insert(next_blk)
      end
      i = i + 2

    -- Standalone Table: needspace based on row count
    elseif blk.t == "Table" then
      local rows = table_row_count(blk)
      local cm = math.max(3, (rows + 2) * 0.7)
      new:insert(pandoc.RawBlock("latex",
        string.format("\\needspace{%.1fcm}", cm)))
      new:insert(blk)
      i = i + 1

    -- Standalone CodeBlock: minipage for short blocks
    elseif blk.t == "CodeBlock" then
      local lines = code_block_lines(blk)
      if lines <= 30 then
        local cm = math.max(3, (lines + 2) * 0.5)
        new:insert(pandoc.RawBlock("latex",
          string.format("\\needspace{%.1fcm}\n\\begin{minipage}{\\linewidth}", cm)))
        new:insert(blk)
        new:insert(pandoc.RawBlock("latex", "\\end{minipage}"))
      else
        new:insert(pandoc.RawBlock("latex", "\\needspace{5cm}"))
        new:insert(blk)
      end
      i = i + 1

    else
      new:insert(blk)
      i = i + 1
    end
  end

  return new
end
