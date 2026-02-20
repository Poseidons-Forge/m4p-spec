-- table-widths.lua — Redistribute uniform table columns based on content.
--
-- Problem: pandoc assigns column widths from pipe-table separator dash counts
-- when any row exceeds --columns width.  Separators like |---|---|---| give
-- each column roughly equal width regardless of content, making narrow-content
-- columns (Range, Bit, etc.) far wider than needed — visible as excessive
-- left padding.
--
-- Fix: for tables where column widths are approximately uniform (max/min
-- ratio < 2), redistribute proportional to sqrt(max_cell_length).  sqrt
-- compresses the ratio so a column with 10x the content gets ~3.2x the
-- width, not 10x.  Tables with deliberately varied separator dashes
-- (max/min ratio >= 2) are left untouched.

function Table(tbl)
  local n = #tbl.colspecs
  if n < 2 then return end

  -- ColWidthDefault (0) means auto-sized — skip those.
  local min_w, max_w = math.huge, 0
  for i = 1, n do
    local w = tbl.colspecs[i][2]
    if type(w) ~= "number" or w == 0 then return end
    if w < min_w then min_w = w end
    if w > max_w then max_w = w end
  end

  -- If the widest column is >= 2x the narrowest, the separator dashes were
  -- deliberately varied — leave the table alone.
  if max_w / min_w >= 2.0 then return end

  -- Measure max content length (characters) per column across all rows.
  local max_len = {}
  for i = 1, n do max_len[i] = 1 end

  local function measure_row(row)
    for i, cell in ipairs(row.cells) do
      if i <= n then
        local len = #pandoc.utils.stringify(cell.contents)
        if len > max_len[i] then max_len[i] = len end
      end
    end
  end

  for _, row in ipairs(tbl.head.rows) do measure_row(row) end
  for _, body in ipairs(tbl.bodies) do
    for _, row in ipairs(body.body) do measure_row(row) end
  end

  -- Redistribute using sqrt of max content length.
  local total = 0
  local new_w = {}
  for i = 1, n do
    new_w[i] = math.sqrt(max_len[i])
    total = total + new_w[i]
  end

  -- Build new colspecs preserving alignment.
  local new_colspecs = {}
  for i = 1, n do
    new_colspecs[i] = {tbl.colspecs[i][1], new_w[i] / total}
  end
  tbl.colspecs = new_colspecs

  return tbl
end
