#!/usr/bin/env node
/**
 * Render mermaid diagrams with figure-number filenames.
 *
 * Usage:  node render.js [svg|png|pdf] [input.md ...]
 *
 * If no input files are provided, this script reads ordered section names from
 * sections/order.txt and renders all listed markdown files.
 *
 * Extracts each ```mermaid block, determines its Figure number from the
 * nearest preceding heading containing "Figure N", and renders via mmdc.
 * Figures with multiple diagrams get a/b/c suffixes (e.g. figure-7a.svg).
 */
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const FMT = process.argv[2] || "svg";
const INPUT_ARGS = process.argv.slice(3);
const OUT = path.join(__dirname, "rendered");
const MMDC = path.join(__dirname, "node_modules", ".bin", "mmdc");
const SCALE = FMT === "png" ? "-s 2" : "";
const PDF_SCALE = 0.75;  // Scale factor for PDF diagrams (prevents them
                          // from filling the entire text width).
const ORDER_FILE = path.join(__dirname, "sections", "order.txt");

function defaultInputs() {
  if (fs.existsSync(ORDER_FILE)) {
    const ordered = fs.readFileSync(ORDER_FILE, "utf-8")
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line && !line.startsWith("#"))
      .map((fileName) => path.join("sections", fileName))
      .filter((relPath) => fs.existsSync(path.join(__dirname, relPath)));

    if (ordered.length > 0) {
      return ordered;
    }
  }

  throw new Error("no inputs provided and sections/order.txt is missing or empty");
}

function resolveOutputPath(inputPath) {
  if (path.isAbsolute(inputPath)) {
    return path.basename(inputPath);
  }
  return inputPath.replace(/^\.\//, "");
}

const INPUTS = INPUT_ARGS.length > 0 ? INPUT_ARGS : defaultInputs();

const SOURCES = INPUTS.map((inputPath) => {
  const srcPath = path.isAbsolute(inputPath)
    ? inputPath
    : path.join(__dirname, inputPath);

  if (!fs.existsSync(srcPath)) {
    throw new Error(`input not found: ${inputPath}`);
  }

  return {
    inputPath,
    srcPath,
    outPath: resolveOutputPath(inputPath),
    markdown: fs.readFileSync(srcPath, "utf-8"),
  };
});
// Puppeteer config for running in Docker (--no-sandbox).
const PUPPETEER_CFG = "/opt/puppeteer-config.json";
const PPARGS = fs.existsSync(PUPPETEER_CFG) ? ` -p "${PUPPETEER_CFG}"` : "";
fs.mkdirSync(OUT, { recursive: true });

// Avoid stale diagram reuse when a render later fails.
const FIGURE_FILE = new RegExp(`^figure-\\d+[a-z]?\\.${FMT}$`);
for (const entry of fs.readdirSync(OUT)) {
  if (FIGURE_FILE.test(entry)) {
    fs.rmSync(path.join(OUT, entry), { force: true });
  }
}

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

console.log("  sources:");
for (const source of SOURCES) {
  console.log(`    ${source.inputPath}`);
}

// Parse all source files in order, tracking current figure number and blocks.
const blocks = []; // { figNum, subIndex, code, sourceIndex }
const sourceBlocks = SOURCES.map(() => []);
const figCount = {}; // figNum -> how many blocks seen so far

for (const [sourceIndex, source] of SOURCES.entries()) {
  const lines = source.markdown.split("\n");
  let currentFig = null;
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
        const block = {
          figNum: currentFig,
          subIndex: figCount[currentFig],
          code: blockLines.join("\n"),
          sourceIndex,
        };
        blocks.push(block);
        sourceBlocks[sourceIndex].push(block);
      }
      continue;
    }

    if (inBlock) {
      blockLines.push(line);
    }
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
const renderFailures = [];

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
    renderFailures.push({
      name,
      error: err.stderr?.toString().trim() || err.message,
    });
  }
}

// Clean up temp files
fs.rmSync(tmpDir, { recursive: true, force: true });
fs.rmSync(CUSTOM_CSS, { force: true });

if (renderFailures.length > 0) {
  console.error(`\nRender failed for ${renderFailures.length} diagram(s).`);
  for (const failure of renderFailures) {
    console.error(`  - ${failure.name}: ${failure.error}`);
  }
  process.exit(1);
}

// Generate rendered markdown files with figure-named image refs.
for (const [sourceIndex, source] of SOURCES.entries()) {
  const blocksForSource = sourceBlocks[sourceIndex];
  let blockIdx = 0;

  const outMd = source.markdown.replace(/```mermaid\n[\s\S]*?```/g, (match) => {
    const b = blocksForSource[blockIdx++];
    if (!b) return match; // block had no figure reference — leave as-is
    const suffix =
      figTotals[b.figNum] > 1
        ? String.fromCharCode(96 + b.subIndex)
        : "";
    const name = `figure-${b.figNum}${suffix}`;
    return `![Figure ${b.figNum}${suffix ? ` (${suffix})` : ""}](./${name}.${FMT})`;
  });

  const outFile = path.join(OUT, source.outPath);
  fs.mkdirSync(path.dirname(outFile), { recursive: true });
  fs.writeFileSync(outFile, outMd);
  console.log(`\n  rendered/${source.outPath} (${blocksForSource.length} diagrams)`);
}
