#!/usr/bin/env node
/**
 * Discover routes for Next.js App Router (app/**/page.tsx) and pages/ dir.
 * Run from project root: node scripts/qa-audit/discover-routes.mjs
 */
import fs from "fs";
import path from "path";

const root = process.cwd();
const outDir = path.join(root, "qa-audit");
const outFile = path.join(outDir, "discovery.json");

function walk(dir, acc = []) {
  if (!fs.existsSync(dir)) return acc;
  for (const name of fs.readdirSync(dir)) {
    const full = path.join(dir, name);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      if (name === "node_modules" || name.startsWith(".")) continue;
      walk(full, acc);
    } else if (/^page\.(tsx|jsx|js)$/.test(name)) {
      acc.push(full);
    }
  }
  return acc;
}

function appPathToRoute(file) {
  const rel = path.relative(path.join(root, "app"), file);
  const segments = rel
    .replace(/\/page\.(tsx|jsx|js)$/, "")
    .split(path.sep)
    .filter((s) => !(s.startsWith("(") && s.endsWith(")"))); // route groups
  const route =
    "/" +
    segments
      .map((s) => s.replace(/\[\.\.\.(\w+)\]/, "*").replace(/\[(\w+)\]/, ":$1"))
      .join("/");
  return route === "/" ? "/" : route.replace(/\/+/g, "/").replace(/\/$/, "") || "/";
}

const appPages = walk(path.join(root, "app"));
const pagesDir = path.join(root, "pages");
const legacyPages = fs.existsSync(pagesDir)
  ? walk(pagesDir).filter(
      (f) => !f.includes("_app") && !f.includes("_document") && !f.includes("api/")
    )
  : [];

const routes = [
  ...appPages.map((file) => ({
    path: appPathToRoute(file),
    file: path.relative(root, file),
    framework: "next-app",
    auth: /dashboard|admin|settings|account/i.test(file),
  })),
  ...legacyPages.map((file) => {
    const rel = path.relative(pagesDir, file).replace(/\.(tsx|jsx|js)$/, "");
    const route = "/" + rel.replace(/\/index$/, "").replace(/index$/, "");
    return {
      path: route === "/" ? "/" : route,
      file: path.relative(root, file),
      framework: "next-pages",
      auth: /dashboard|admin/i.test(file),
    };
  }),
];

const unique = [...new Map(routes.map((r) => [r.path, r])).values()].sort((a, b) =>
  a.path.localeCompare(b.path)
);

const apiFiles = walk(path.join(root, "app")).filter((f) =>
  /route\.(ts|js)$/.test(f)
);

const discovery = {
  generatedAt: new Date().toISOString(),
  projectRoot: root,
  routes: unique,
  apiRoutes: apiFiles.map((file) => ({
    file: path.relative(root, file),
    path: inferApiPath(file),
  })),
  counts: {
    routes: unique.length,
    apiRoutes: apiFiles.length,
  },
};

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(outFile, JSON.stringify(discovery, null, 2));
console.log(`Wrote ${outFile} — ${unique.length} routes, ${apiFiles.length} API route files`);

function inferApiPath(file) {
  const rel = path.relative(path.join(root, "app"), file).replace(/\/route\.(ts|js)$/, "");
  return "/api/" + rel.split(path.sep).slice(1).join("/");
}
