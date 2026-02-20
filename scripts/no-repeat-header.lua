-- no-repeat-header.lua — Suppress repeated headers on longtable continuation pages.
--
-- Problem: pandoc's LaTeX writer generates longtable environments that repeat
-- the column header row on every continuation page.  For tables that begin at
-- the top of a page (after a page break), both the first-page header and the
-- continuation header can render, producing a visible duplicate.
--
-- Fix: convert each Table AST node to raw LaTeX and replace the continuation
-- header section (between \endfirsthead and \endhead) with an empty \endhead,
-- so headers only appear once.
--
-- This filter MUST run after table-widths.lua and keep-together.lua so that
-- column width adjustments and needspace directives are already applied.

function Table(tbl)
  local doc = pandoc.Pandoc({tbl})
  local latex = pandoc.write(doc, 'latex')

  -- Case 1: Both \endfirsthead and \endhead present — strip continuation
  -- header content (everything between the two markers).
  latex = latex:gsub(
    "(\\endfirsthead%s*\n)(.-)(\n%s*\\endhead)",
    "%1%3"
  )

  -- Case 2: Only \endhead, no \endfirsthead — pandoc versions that omit
  -- \endfirsthead use \endhead for ALL pages (first + continuation).
  -- Insert \endfirsthead so the first-page header is preserved and the
  -- continuation header becomes empty.
  if not latex:find("\\endfirsthead") then
    latex = latex:gsub(
      "(\\endhead)",
      "\\endfirsthead\n%1"
    )
  end

  return pandoc.RawBlock("latex", latex)
end
