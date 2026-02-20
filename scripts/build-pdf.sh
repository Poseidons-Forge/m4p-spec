#!/usr/bin/env bash
#
# build-pdf.sh — Render the M4P Protocol Specification as a styled PDF.
#
# Pipeline:
#   1. Render mermaid diagrams to PDF vector images  (render.js + mmdc)
#   2. Preprocess rendered markdown  (strip manual TOC / title block)
#   3. pandoc  +  eisvogel template  +  xelatex  →  final PDF
#
# Usage:
#   ./scripts/build-pdf.sh          # from repo root
#   npm run pdf                     # via npm
#
# Prerequisites:
#   node, pandoc, xelatex  (apt install pandoc texlive-xetex texlive-latex-extra)
#   npm install                     (for @mermaid-js/mermaid-cli)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RENDERED_DIR="$PROJECT_DIR/rendered"
CACHE_DIR="$SCRIPT_DIR/.cache"
TEMPLATE="$CACHE_DIR/eisvogel.latex"
METADATA="$SCRIPT_DIR/pdf-metadata.yaml"
OUTPUT="$PROJECT_DIR/m4p-spec.pdf"
INPUT_MD="m4p-spec.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m%s\033[0m\n' "$1"; }
die()  { printf '\033[0;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in node pandoc xelatex; do
    command -v "$cmd" >/dev/null || die "$cmd is required but not found"
done
[ -f "$PROJECT_DIR/render.js" ] || die "render.js not found in $PROJECT_DIR"
[ -f "$METADATA" ]             || die "pdf-metadata.yaml not found in $SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Step 1  —  Render mermaid diagrams to PDF (vector)
# ---------------------------------------------------------------------------
step "Rendering mermaid diagrams to PDF..."
(cd "$PROJECT_DIR" && node render.js pdf)
NDIAG=$(find "$RENDERED_DIR" -maxdepth 1 -name 'figure-*.pdf' 2>/dev/null | wc -l)
ok "$NDIAG diagram(s) rendered"

# ---------------------------------------------------------------------------
# Step 2  —  Download eisvogel template (cached)
# ---------------------------------------------------------------------------
mkdir -p "$CACHE_DIR"
if [ ! -f "$TEMPLATE" ]; then
    step "Downloading eisvogel template..."
    EISVOGEL_URL="https://github.com/Wandmalfarbe/pandoc-latex-template/releases/latest/download/Eisvogel.tar.gz"
    curl -fsSL "$EISVOGEL_URL" \
        | tar xz -C "$CACHE_DIR" --strip-components=1 --wildcards '*/eisvogel.latex' \
        || die "Failed to download eisvogel template"
    [ -f "$TEMPLATE" ] || die "eisvogel.latex not found after extraction"
    ok "cached at scripts/.cache/eisvogel.latex"
else
    ok "eisvogel template cached"
fi

# ---------------------------------------------------------------------------
# Step 3  —  Preprocess markdown
# ---------------------------------------------------------------------------
step "Preparing markdown for pandoc..."
PREPARED="$RENDERED_DIR/.prepared.md"

# The source has:  # Title  /  ## Subtitle  /  metadata table  /  manual TOC
# Eisvogel generates a title page + auto-TOC from YAML metadata, so we strip
# everything before the first real content section.
sed -n '/^## 1\. Introduction/,$p' "$RENDERED_DIR/$INPUT_MD" > "$PREPARED"
ok "stripped title block and manual TOC"

# Extract version and date from the markdown metadata table so the PDF title
# page and headers stay in sync with the source document.
SPEC_VERSION=$(grep -oP '\*\*Version\*\*\s*\|\s*\K[^\s|]+' "$RENDERED_DIR/$INPUT_MD" || echo "0.0")
SPEC_DATE=$(grep -oP '\*\*Date\*\*\s*\|\s*\K[^\s|]+' "$RENDERED_DIR/$INPUT_MD" || echo "unknown")

# Build a resolved copy of the metadata YAML with placeholders replaced.
RESOLVED_METADATA="$RENDERED_DIR/.pdf-metadata.yaml"
sed -e "s/VERSION_PLACEHOLDER/$SPEC_VERSION/g" \
    -e "s/DATE_PLACEHOLDER/$SPEC_DATE/g" \
    "$METADATA" > "$RESOLVED_METADATA"
ok "version $SPEC_VERSION, date $SPEC_DATE from source markdown"

# Symlink assets into rendered/ so logo paths resolve during xelatex build.
# Also create a space-free symlink for the logo (LaTeX chokes on spaces).
ln -sfn "$PROJECT_DIR/assets" "$RENDERED_DIR/assets"
ln -sf "$PROJECT_DIR/assets/PSFi Horizontal for White Background.png" "$RENDERED_DIR/assets/logo.png"
ln -sf "$PROJECT_DIR/assets/PSFi Horizontal for Black Background.png" "$RENDERED_DIR/assets/logo-dark.png"
ok "linked assets directory"

# ---------------------------------------------------------------------------
# Step 4  —  Build PDF
# ---------------------------------------------------------------------------
step "Building PDF (pandoc + xelatex + eisvogel)..."
HEADER_TEX="$SCRIPT_DIR/header.tex"
LUA_FILTER="$SCRIPT_DIR/needspace-images.lua"
LUA_TABLE_WIDTHS="$SCRIPT_DIR/table-widths.lua"
LUA_KEEP_TOGETHER="$SCRIPT_DIR/keep-together.lua"
LUA_NO_REPEAT_HDR="$SCRIPT_DIR/no-repeat-header.lua"
(cd "$RENDERED_DIR" && pandoc ".prepared.md" \
    --from markdown-implicit_figures \
    --metadata-file="$RESOLVED_METADATA" \
    --template="$TEMPLATE" \
    --include-in-header="$HEADER_TEX" \
    --lua-filter="$LUA_TABLE_WIDTHS" \
    --lua-filter="$LUA_KEEP_TOGETHER" \
    --lua-filter="$LUA_NO_REPEAT_HDR" \
    --lua-filter="$LUA_FILTER" \
    --pdf-engine=xelatex \
    --toc --toc-depth=3 \
    --shift-heading-level-by=-1 \
    --columns=72 \
    --highlight-style=tango \
    -o "$OUTPUT" \
)

# ---------------------------------------------------------------------------
# Cleanup & report
# ---------------------------------------------------------------------------
rm -f "$PREPARED" "$RESOLVED_METADATA"

if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    PAGES=$(pdfinfo "$OUTPUT" 2>/dev/null | awk '/^Pages:/{print $2}' || echo "?")
    step "Done"
    ok "$(basename "$OUTPUT")  --  ${SIZE}, ${PAGES} pages"
else
    die "PDF was not created"
fi
