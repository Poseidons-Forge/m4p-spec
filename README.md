# M4P Protocol Specification

This repository contains the M4P Protocol Specification split across
`sections/*.md` and a build pipeline that renders it as a professionally styled
PDF using Pandoc, XeLaTeX, and the
[Eisvogel](https://github.com/Wandmalfarbe/pandoc-latex-template) LaTeX
template.

For the reference implementation, see the [m4p](https://github.com/pschanely/m4p)
repository.

## Build the PDF

### With Docker (recommended)

```bash
./build.sh
```

This builds a Docker image with all dependencies and produces `m4p-spec.pdf`
in the repo root.

### Without Docker

Install the system prerequisites:

```bash
# Node.js (for mermaid diagram rendering)
# https://nodejs.org/ or via your package manager

# Pandoc + XeLaTeX + fonts
sudo apt install pandoc texlive-xetex texlive-latex-extra \
    texlive-latex-recommended fonts-noto-serif fonts-noto-sans \
    fonts-dejavu-core poppler-utils
```

Then build:

```bash
npm install      # first time only — installs @mermaid-js/mermaid-cli
npm run pdf      # builds m4p-spec.pdf
```

## How It Works

The build script (`scripts/build-pdf.sh`) runs a four-step pipeline:

1. **Render diagrams** -- `render.js` extracts Mermaid blocks from the
   section markdown files and renders them as PDF vector images via `mmdc`.
2. **Resolve metadata + section order** -- Reads `sections/order.txt`, excludes
   `00-frontmatter.md` (Eisvogel generates title page + ToC), and injects
   values from `spec-metadata.yaml` into `scripts/pdf-metadata.yaml`.
3. **Pandoc + Eisvogel + XeLaTeX** -- Converts the processed markdown into
   a styled PDF. Configuration lives in `scripts/pdf-metadata.yaml` and
   `scripts/header.tex`.
4. **Output** -- `m4p-spec.pdf` in the repo root.

The Eisvogel LaTeX template is downloaded automatically on first build and
cached in `scripts/.cache/`.

## File Reference

| File | Purpose |
|---|---|
| `sections/*.md` | Specification source split by section |
| `sections/order.txt` | Explicit section ordering for render/build |
| `spec-metadata.yaml` | Canonical version/status/date values |
| `render.js` | Mermaid diagram extractor and renderer |
| `package.json` | npm dependencies (mermaid-cli, layout-elk) |
| `Dockerfile` | Reproducible PDF build environment |
| `build.sh` | One-command Docker build wrapper |
| `scripts/build-pdf.sh` | Main build script (Pandoc + XeLaTeX orchestration) |
| `scripts/pdf-metadata.yaml` | Eisvogel config: title page, headers/footers, fonts |
| `scripts/header.tex` | LaTeX preamble: Unicode font fallbacks, image sizing |
| `scripts/svg2pdf.js` | SVG to PDF conversion via Puppeteer |
| `scripts/*.lua` | Pandoc Lua filters for table/image/code layout |
| `assets/` | Logo images used on the PDF title page |

## Troubleshooting

- **Missing fonts**: Install via `sudo apt install fonts-noto fonts-dejavu`.
- **Unicode warnings**: Add missing characters to the `\newunicodechar` block
  in `scripts/header.tex`.
- **Eisvogel re-download**: Delete `scripts/.cache/` and re-run.
- **Mermaid failures**: Check that `npx mmdc --version` works. If Puppeteer/
  Chromium errors occur, try `PUPPETEER_ARGS='--no-sandbox' npm run pdf`.

## License

The specification is licensed under CC BY 4.0.

SPDX identifier: `CC-BY-4.0`

[![License: CC BY 4.0](https://licensebuttons.net/l/by/4.0/88x31.png)](https://creativecommons.org/licenses/by/4.0/)

This specification is licensed under the Creative Commons Attribution 4.0 International License. You are free to share and adapt this material for any purpose, including commercial, provided you give appropriate credit to Poseidon's Forge, Inc. and indicate if changes were made. Note that the 'M4P' and 'Maritime Multi-Modal Mesh Protocol' names are unregistered trademarks of Poseidon's Forge, Inc. -- modified versions of this specification may not use these names to imply official status or endorsement without written permission. This license applies to the specification documents only -- the software implementation is licensed separately under the Apache License 2.0.
