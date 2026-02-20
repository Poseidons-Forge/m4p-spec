#!/usr/bin/env node
/**
 * Render mermaid diagrams with figure-number filenames.
 *
 * Usage:  node render.js [svg|png|pdf] [input.md]
 *
 * Extracts each ```mermaid block, determines its Figure number from the
 * nearest preceding heading containing "Figure N", and renders via mmdc.
 * Figures with multiple diagrams get a/b/c suffixes (e.g. figure-7a.svg).
 *
 * Default input: m4p-spec.md (falls back to spec_diagrams.md)
 */
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const FMT = process.argv[2] || "svg";
const INPUT = process.argv[3]
  || (fs.existsSync(path.join(__dirname, "m4p-spec.md"))
    ? "m4p-spec.md"
    : "spec_diagrams.md");

const SRC = path.join(__dirname, INPUT);
const OUT = path.join(__dirname, "rendered");
const MMDC = path.join(__dirname, "node_modules", ".bin", "mmdc");
const SCALE = FMT === "png" ? "-s 2" : "";
const PDF_SCALE = 0.75;  // Scale factor for PDF diagrams (prevents them
                          // from filling the entire text width).
// Puppeteer config for running in Docker (--no-sandbox).
const PUPPETEER_CFG = "/opt/puppeteer-config.json";
const PPARGS = fs.existsSync(PUPPETEER_CFG) ? ` -p "${PUPPETEER_CFG}"` : "";
fs.mkdirSync(OUT, { recursive: true });

// Custom CSS to force all text in mermaid SVGs to render as solid black.
// This overrides any theme styling at the SVG/CSS level, which is more
// reliable than trying to set every mermaid themeVariable.
const CUSTOM_CSS = path.join(OUT, ".mermaid-overrides.css");
fs.writeFileSync(CUSTOM_CSS, [
  "* { color: #000000 !important; }",
  "text, tspan, .label, .nodeLabel, .edgeLabel, .cluster-label,",
  ".statediagram-state .state-title, .er.entityLabel,",
  ".messageText, .loopText, .labelText, text.actor, .noteText {",
  "  fill: #000000 !important;",
  "  color: #000000 !important;",
  "}",
  ".edge-pattern-dotted, .flowchart-link, .transition, .relation {",
  "  stroke: #333333 !important;",
  "}",
].join("\n"));

console.log(`  source: ${INPUT}`);

const md = fs.readFileSync(SRC, "utf-8");
const lines = md.split("\n");

// Parse: walk lines, track current figure number, collect mermaid blocks
const blocks = []; // { figNum, subIndex, code }
let currentFig = null;
const figCount = {}; // figNum -> how many blocks seen so far
let inBlock = false;
let blockLines = [];

for (const line of lines) {
  // Use the LAST "Figure N" reference on a line — prose often says
  // "as in Figure 5 … Figure 6 illustrates the next …" and the last
  // reference is the one that labels the upcoming diagram.
  const figMatches = [...line.matchAll(/[Ff]igure (\d+)/g)];
  if (figMatches.length > 0 && !inBlock) {
    const num = parseInt(figMatches[figMatches.length - 1][1], 10);
    if (num !== currentFig) {
      currentFig = num;
      if (!figCount[currentFig]) figCount[currentFig] = 0;
    }
  }

  if (line.trim() === "```mermaid") {
    inBlock = true;
    blockLines = [];
    continue;
  }

  if (inBlock && line.trim() === "```") {
    inBlock = false;
    if (currentFig != null) {
      figCount[currentFig]++;
      blocks.push({
        figNum: currentFig,
        subIndex: figCount[currentFig],
        code: blockLines.join("\n"),
      });
    }
    continue;
  }

  if (inBlock) {
    blockLines.push(line);
  }
}

// Determine which figures have multiple diagrams
const figTotals = {};
for (const b of blocks) {
  figTotals[b.figNum] = Math.max(figTotals[b.figNum] || 0, b.subIndex);
}

// Render each block
const tmpDir = path.join(OUT, ".tmp");
fs.mkdirSync(tmpDir, { recursive: true });

for (const b of blocks) {
  const suffix =
    figTotals[b.figNum] > 1
      ? String.fromCharCode(96 + b.subIndex) // a, b, c...
      : "";
  const name = `figure-${b.figNum}${suffix}`;
  const inFile = path.join(tmpDir, `${name}.mmd`);
  const outFile = path.join(OUT, `${name}.${FMT}`);

  fs.writeFileSync(inFile, b.code);

  try {
    if (FMT === "pdf") {
      // For PDF: render SVG first (always single-page), then convert to
      // PDF via puppeteer with a page size matching the SVG dimensions.
      // This avoids mmdc's built-in PDF renderer which paginates tall
      // diagrams across multiple letter-size pages, breaking the output.
      const svgFile = path.join(tmpDir, `${name}.svg`);
      execSync(
        `"${MMDC}" -i "${inFile}" -o "${svgFile}" -e svg -b white --cssFile "${CUSTOM_CSS}"${PPARGS} -q`,
        { stdio: "pipe" }
      );
      const svg2pdf = path.join(__dirname, "scripts", "svg2pdf.js");
      execSync(
        `node "${svg2pdf}" "${svgFile}" "${outFile}" ${PDF_SCALE}`,
        { stdio: "pipe" }
      );
    } else {
      execSync(
        `"${MMDC}" -i "${inFile}" -o "${outFile}" -e ${FMT} ${SCALE} -b white --cssFile "${CUSTOM_CSS}"${PPARGS} -q`,
        { stdio: "pipe" }
      );
    }

    console.log(`  ${name}.${FMT}`);
  } catch (err) {
    console.error(`  FAILED: ${name} — ${err.stderr?.toString().trim()}`);
  }
}

// Clean up temp files
fs.rmSync(tmpDir, { recursive: true, force: true });
fs.rmSync(CUSTOM_CSS, { force: true });

// Generate rendered markdown with figure-named image refs
const outName = path.basename(INPUT);
let outMd = md;
let blockIdx = 0;
outMd = outMd.replace(/```mermaid\n[\s\S]*?```/g, (match) => {
  const b = blocks[blockIdx++];
  if (!b) return match; // block had no figure reference — leave as-is
  const suffix =
    figTotals[b.figNum] > 1
      ? String.fromCharCode(96 + b.subIndex)
      : "";
  const name = `figure-${b.figNum}${suffix}`;
  return `![Figure ${b.figNum}${suffix ? ` (${suffix})` : ""}](./${name}.${FMT})`;
});
fs.writeFileSync(path.join(OUT, outName), outMd);
console.log(`\n  rendered/${outName} (${blocks.length} diagrams)`);
