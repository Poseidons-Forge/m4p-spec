#!/usr/bin/env bash
#
# build-pdf.sh — Render the M4P Protocol Specification as a styled PDF.
#
# Pipeline:
#   1. Render mermaid diagrams to PDF vector images  (render.js + mmdc)
#   2. Resolve metadata + ordered section inputs
#   3. pandoc  +  eisvogel template  +  xelatex  →  final PDF
#
# Usage:
#   ./scripts/build-pdf.sh          # from repo root
#   ./scripts/build-pdf.sh --skip-figures
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
SECTION_DIR="$PROJECT_DIR/sections"
SECTION_ORDER="$SECTION_DIR/order.txt"
CACHE_DIR="$SCRIPT_DIR/.cache"
TEMPLATE="$CACHE_DIR/eisvogel.latex"
METADATA="$SCRIPT_DIR/pdf-metadata.yaml"
SPEC_METADATA="$PROJECT_DIR/spec-metadata.yaml"
OUTPUT="$PROJECT_DIR/m4p-spec.pdf"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[0;32m%s\033[0m\n' "$1"; }
die()  { printf '\033[0;31mERROR: %s\033[0m\n' "$1" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: ./scripts/build-pdf.sh [--skip-figures]

Options:
  --skip-figures   Reuse existing rendered diagrams/markdown under rendered/
                   and skip running render.js.
EOF
}

SKIP_FIGURES=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-figures)
            SKIP_FIGURES=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

extract_spec_metadata() {
    local key="$1"
    local value

    value=$(awk -v key="$key" '
        $0 ~ "^[[:space:]]*" key "[[:space:]]*:" {
            val = $0
            sub("^[[:space:]]*" key "[[:space:]]*:[[:space:]]*", "", val)
            sub(/[[:space:]]*#.*/, "", val)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)

            first = substr(val, 1, 1)
            last = substr(val, length(val), 1)
            if ((first == "\"" && last == "\"") || (first == "'"'"'" && last == "'"'"'")) {
                val = substr(val, 2, length(val) - 2)
            }

            print val
            exit
        }
    ' "$SPEC_METADATA")

    [ -n "$value" ] || die "Missing or empty '$key' in $SPEC_METADATA"
    printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in node pandoc xelatex; do
    command -v "$cmd" >/dev/null || die "$cmd is required but not found"
done
[ -f "$PROJECT_DIR/render.js" ] || die "render.js not found in $PROJECT_DIR"
[ -d "$SECTION_DIR" ]          || die "sections directory not found in $PROJECT_DIR"
[ -f "$SECTION_ORDER" ]        || die "sections/order.txt not found in $SECTION_DIR"
[ -f "$METADATA" ]             || die "pdf-metadata.yaml not found in $SCRIPT_DIR"
[ -f "$SPEC_METADATA" ]        || die "spec-metadata.yaml not found in $PROJECT_DIR"

# ---------------------------------------------------------------------------
# Step 1  —  Render mermaid diagrams to PDF (vector)
# ---------------------------------------------------------------------------
if [ "$SKIP_FIGURES" -eq 1 ]; then
    step "Skipping mermaid diagram rendering (--skip-figures)..."
    [ -d "$RENDERED_DIR/sections" ] || die "rendered/sections not found; run without --skip-figures first"
    ok "using existing rendered artifacts"
else
    step "Rendering mermaid diagrams to PDF..."
    (cd "$PROJECT_DIR" && node render.js pdf)
    NDIAG=$(find "$RENDERED_DIR" -maxdepth 1 -name 'figure-*.pdf' 2>/dev/null | wc -l)
    ok "$NDIAG diagram(s) rendered"
fi

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
# Step 3  —  Resolve metadata and ordered section inputs
# ---------------------------------------------------------------------------
step "Preparing metadata and section inputs for pandoc..."

mapfile -t ORDERED_SECTIONS < <(grep -vE '^[[:space:]]*($|#)' "$SECTION_ORDER")
[ "${#ORDERED_SECTIONS[@]}" -gt 0 ] || die "No sections listed in $SECTION_ORDER"

PANDOC_INPUTS=()
for section_file in "${ORDERED_SECTIONS[@]}"; do
    rendered_section="$RENDERED_DIR/sections/$section_file"
    [ -f "$rendered_section" ] || die "Rendered section missing: $rendered_section"

    # 00-frontmatter.md contains the source title block + manual TOC, which
    # Eisvogel regenerates from metadata and --toc.
    if [ "$section_file" != "00-frontmatter.md" ]; then
        PANDOC_INPUTS+=("sections/$section_file")
    fi
done
[ "${#PANDOC_INPUTS[@]}" -gt 0 ] || die "No content sections selected for pandoc"
ok "${#PANDOC_INPUTS[@]} section file(s) selected"

# Extract version/status/date from dedicated spec metadata.
SPEC_VERSION=$(extract_spec_metadata version)
SPEC_STATUS=$(extract_spec_metadata status)
SPEC_DATE=$(extract_spec_metadata date)

# Build a resolved copy of the metadata YAML with placeholders replaced.
RESOLVED_METADATA="$RENDERED_DIR/.pdf-metadata.yaml"
sed -e "s/VERSION_PLACEHOLDER/$SPEC_VERSION/g" \
    -e "s/STATUS_PLACEHOLDER/$SPEC_STATUS/g" \
    -e "s/DATE_PLACEHOLDER/$SPEC_DATE/g" \
    "$METADATA" > "$RESOLVED_METADATA"
ok "version $SPEC_VERSION, status $SPEC_STATUS, date $SPEC_DATE from spec metadata"

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
(cd "$RENDERED_DIR" && pandoc "${PANDOC_INPUTS[@]}" \
    --from markdown-implicit_figures \
    --resource-path="$RENDERED_DIR:$RENDERED_DIR/sections" \
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
rm -f "$RESOLVED_METADATA"

if [ -f "$OUTPUT" ]; then
    SIZE=$(du -h "$OUTPUT" | cut -f1)
    PAGES=$(pdfinfo "$OUTPUT" 2>/dev/null | awk '/^Pages:/{print $2}' || echo "?")
    step "Done"
    ok "$(basename "$OUTPUT")  --  ${SIZE}, ${PAGES} pages"
else
    die "PDF was not created"
fi
