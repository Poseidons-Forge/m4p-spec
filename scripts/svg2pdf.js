#!/usr/bin/env node
/**
 * svg2pdf.js — Convert an SVG file to a single-page PDF whose page size
 * matches the SVG dimensions (scaled by a configurable factor).
 *
 * Uses puppeteer (bundled with @mermaid-js/mermaid-cli) so no extra
 * system dependencies are needed.
 *
 * Usage:  node svg2pdf.js <input.svg> <output.pdf> [scale]
 *
 *   scale  — multiplier applied to the SVG dimensions (default 0.75).
 *            At 0.75 diagrams don't fill the entire text width in the
 *            final eisvogel PDF.
 */
const puppeteer = require("puppeteer");
const fs = require("fs");
const path = require("path");

const [svgPath, pdfPath, scaleArg] = process.argv.slice(2);
if (!svgPath || !pdfPath) {
  console.error("Usage: svg2pdf.js <input.svg> <output.pdf> [scale]");
  process.exit(1);
}

const PDF_SCALE = parseFloat(scaleArg) || 0.75;

(async () => {
  const svg = fs.readFileSync(svgPath, "utf-8");

  // Parse viewBox to determine natural dimensions
  const vbMatch = svg.match(/viewBox="([\d.\-]+)\s+([\d.\-]+)\s+([\d.]+)\s+([\d.]+)"/);
  if (!vbMatch) {
    console.error("Could not parse viewBox from SVG");
    process.exit(1);
  }
  const svgW = parseFloat(vbMatch[3]);
  const svgH = parseFloat(vbMatch[4]);

  // Page size in CSS pixels (px ≈ pt at 96 dpi, but puppeteer pdf() uses
  // inches internally; 1 CSS px = 1/96 inch).
  const pageW = svgW * PDF_SCALE;
  const pageH = svgH * PDF_SCALE;

  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });
  const page = await browser.newPage();

  // Load SVG in an HTML wrapper that eliminates all margins and sizes the
  // SVG to fill the page exactly.
  const html = `<!DOCTYPE html>
<html><head><style>
  * { margin: 0; padding: 0; }
  body { width: ${pageW}px; height: ${pageH}px; overflow: hidden; }
  svg { width: 100%; height: 100%; }
</style></head>
<body>${svg}</body></html>`;

  await page.setContent(html, { waitUntil: "networkidle0" });
  await page.pdf({
    path: pdfPath,
    width: `${pageW}px`,
    height: `${pageH}px`,
    printBackground: true,
    margin: { top: 0, right: 0, bottom: 0, left: 0 },
  });

  await browser.close();
})();
