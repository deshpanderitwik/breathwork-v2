import { defineConfig } from "tsup";

// Two outputs:
//   1. ES module for web — apps/web imports @breathe/core directly.
//   2. IIFE bundle for JavaScriptCore — swift/BreathRuntime loads this as a
//      string and evaluates it inside a JSContext. The global `Breathe` holds
//      the exported API.
export default defineConfig([
  {
    entry: ["src/index.ts"],
    format: ["esm"],
    dts: true,
    sourcemap: true,
    clean: true,
    target: "es2022",
  },
  {
    entry: { "core.iife": "src/index.ts" },
    format: ["iife"],
    globalName: "Breathe",
    dts: false,
    sourcemap: false,
    clean: false,
    target: "es2020",
    minify: false,
    outExtension: () => ({ js: ".js" }),
  },
]);
