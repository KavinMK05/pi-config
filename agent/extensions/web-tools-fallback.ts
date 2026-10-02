/**
 * Web-tool naming wrapper.
 *
 * Why this exists
 * ---------------
 * donsetch, pi-searxng-search and pi-smart-fetch all claim the same tool names
 * (`web_search`, `web_fetch`). pi's tool registry is a plain Map in
 * `_refreshToolRegistry` (dist/core/agent-session.js), so whichever extension
 * registers last silently overwrites the others -- no error, no warning. With
 * all three loaded unmodified, donsetch (listed last) shadows searxng's
 * `web_search` and smart-fetch's `web_fetch`.
 *
 * This extension re-registers their tools under disjoint names instead:
 *
 *   web_search               -> searxng      (primary)
 *   web_search_fallback      -> donsetch     (fallback)
 *   web_fetch                -> donsetch     (primary)
 *   web_fetch_fallback       -> smart-fetch  (fallback)
 *   batch_web_fetch_fallback -> smart-fetch
 *   web_crawl, web_screenshot -> donsetch    (unchanged)
 *
 * How
 * ---
 * Each package's factory is handed a `pi` whose `registerTool` renames the
 * tool before it reaches pi, plus appends primary/fallback guidance to the
 * description. The package files stay byte-identical, so `pi update
 * --extensions`, a reinstall, or a new machine cannot revert the naming -- the
 * one thing an in-place edit to node_modules could not promise.
 *
 * Because this extension is the only thing registering those tools, all three
 * packages must keep `"extensions": []` in `~/.pi/agent/settings.json`. Drop
 * one of those filters and the package double-registers under its original
 * name and shadows the tool this wrapper set up.
 *
 * Module resolution: `~/.pi/agent/node_modules` is a junction to
 * `~/.pi/agent/npm/node_modules`, so the bare specifiers below resolve from
 * this directory.
 *
 * Known cosmetic wart: both packages render their TUI header from a hardcoded
 * closure name, so the transcript still prints `web_fetch` / `web_search` even
 * though the model calls the renamed tool. The name the model sees -- which is
 * the one that matters for tool choice -- is correct.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import searxngSearch from "pi-searxng-search";
import smartFetch from "pi-smart-fetch";
import donsetch from "donsetch/pi-extension.ts";

type RenameMap = Record<string, string>;

type Annotation = {
  /** Original tool name -> name the model should see. Empty means "keep it". */
  renames: RenameMap;
  /** Final tool name -> text appended to that tool's description. */
  guidance: Record<string, string>;
};

const SEARXNG: Annotation = {
  renames: {},
  guidance: {
    web_search:
      "PRIMARY SEARCH: this is the preferred search tool. If the local SearXNG " +
      "instance is unreachable or returns no usable results, retry once with " +
      "`web_search_fallback`.",
  },
};

const DONSETCH: Annotation = {
  // donsetch keeps web_fetch / web_crawl / web_screenshot; only its search is
  // demoted, because searxng owns the canonical `web_search`.
  renames: {
    web_search: "web_search_fallback",
  },
  guidance: {
    web_fetch:
      "PRIMARY FETCH: this is the preferred fetch tool. If it fails, is blocked " +
      "by anti-bot defences, or returns empty/thin content, retry with " +
      "`web_fetch_fallback`.",
    web_search_fallback:
      "FALLBACK SEARCH: prefer `web_search` (the local SearXNG instance) first. " +
      "Use this when SearXNG is unavailable, misconfigured, or returns no usable " +
      "results.",
  },
};

const SMART_FETCH: Annotation = {
  renames: {
    web_fetch: "web_fetch_fallback",
    batch_web_fetch: "batch_web_fetch_fallback",
  },
  guidance: {
    web_fetch_fallback:
      "FALLBACK FETCH: prefer `web_fetch` first. Use this when `web_fetch` fails, " +
      "is blocked by anti-bot defences, or returns empty/thin content.",
    batch_web_fetch_fallback:
      "FALLBACK FETCH (batch): prefer `web_fetch` per URL first. Use this batch " +
      "variant only when the primary fetch is failing or blocked.",
  },
};

/** Rewrite every renamed tool name inside prose. Longest key wins, so
 *  `batch_web_fetch` is never partially rewritten into `batch_web_fetch_fallback`
 *  by the shorter `web_fetch` rule. `\b` also keeps `web_fetch` from matching
 *  inside `batch_web_fetch` (the underscore is a word character). */
function rewriteProse(value: string, renames: RenameMap): string {
  const keys = Object.keys(renames);
  if (keys.length === 0) return value;
  const pattern = new RegExp(
    `\\b(${keys.sort((a, b) => b.length - a.length).join("|")})\\b`,
    "g",
  );
  return value.replace(pattern, (match) => renames[match] ?? match);
}

function appendGuidance(description: unknown, guidance: string | undefined): unknown {
  if (!guidance) return description;
  const base = typeof description === "string" ? description.trim() : "";
  return base ? `${base}\n\n${guidance}` : guidance;
}

/**
 * Wrap `pi` so that the factory's registerTool calls are rewritten in flight.
 * A Proxy (rather than a spread) keeps every other member exactly as pi built
 * it -- including the closure-bound methods donsetch relies on at session_start.
 */
function annotate(pi: ExtensionAPI, annotation: Annotation): ExtensionAPI {
  const registerTool = (pi as any).registerTool.bind(pi);

  const rewrittenRegisterTool = (tool: any) => {
    const target = annotation.renames[tool.name] ?? tool.name;
    const guidance = annotation.guidance[target];

    if (target === tool.name && !guidance) return registerTool(tool);

    const next: any = {
      ...tool,
      name: target,
      label: target,
    };

    if (typeof tool.description === "string" || guidance) {
      next.description = appendGuidance(
        typeof tool.description === "string"
          ? rewriteProse(tool.description, annotation.renames)
          : tool.description,
        guidance,
      );
    }
    if (typeof tool.promptSnippet === "string") {
      next.promptSnippet = rewriteProse(tool.promptSnippet, annotation.renames);
    }
    if (Array.isArray(tool.promptGuidelines)) {
      next.promptGuidelines = tool.promptGuidelines.map((entry: unknown) =>
        typeof entry === "string" ? rewriteProse(entry, annotation.renames) : entry,
      );
    }

    return registerTool(next);
  };

  return new Proxy(pi, {
    get(target, prop, receiver) {
      if (prop === "registerTool") return rewrittenRegisterTool;
      const value = Reflect.get(target, prop, receiver);
      return typeof value === "function" ? value.bind(target) : value;
    },
  }) as ExtensionAPI;
}

export default function webToolsFallback(pi: ExtensionAPI): void {
  searxngSearch(annotate(pi, SEARXNG));
  donsetch(annotate(pi, DONSETCH));
  smartFetch(annotate(pi, SMART_FETCH));
}
