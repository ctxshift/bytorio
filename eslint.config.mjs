import js from "@eslint/js";
import globals from "globals";
import html from "eslint-plugin-html";

export default [
  { ignores: ["build/**", ".tools/**", "node_modules/**"] },
  {
    files: ["**/*.js", "**/*.mjs", "**/*.html"],
    ...js.configs.recommended,
    languageOptions: { ecmaVersion: "latest", sourceType: "module" },
    rules: {
      ...js.configs.recommended.rules,
      "no-var": "error",
      "prefer-const": "error",
      eqeqeq: ["error", "always"],
      curly: ["error", "all"],
      "no-unused-vars": [
        "error",
        { argsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_", ignoreRestSiblings: true },
      ],
    },
  },
  {
    files: ["**/*.html"],
    plugins: { html },
    languageOptions: { sourceType: "script", globals: globals.browser },
  },
  {
    files: ["*.mjs", "tools/**/*.mjs", "experiments/**/*.mjs"],
    languageOptions: { globals: globals.node },
  },
  {
    files: ["runtime/**/web/*.js", "examples/*-shared/*.js"],
    languageOptions: { globals: { ...globals.browser, ...globals.worker } },
  },
  {
    // Browser verification callbacks are serialized by Playwright.
    files: ["tools/verify-*.mjs", "experiments/**/*.mjs"],
    languageOptions: {
      globals: { ...globals.browser, playerStatus: "readonly", playerAudio: "readonly" },
    },
  },
  {
    files: ["tools/verify-rpg.mjs"],
    languageOptions: { globals: { Module: "readonly" } },
  },
];
