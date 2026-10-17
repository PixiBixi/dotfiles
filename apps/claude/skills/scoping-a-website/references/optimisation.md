# Optimising a site whose design is kept

Rounds 1 to 3 of the interview are already answered: skip them.

## Round 0, measured

Payload sizes (compressed), DOM node count, eager rendering (offscreen sections, autoplaying loops), external dependencies (fonts, CDNs, trackers). Run `scripts/sitemap-inventory.py` on the live site so the plan covers every template, not just the home page.

## One question call

With the multiple-choice question tool, in the user's language:
- Target: rendering and smoothness, network weight, mobile, accessibility and SEO.
- Performance budget: LCP and TBT figures, recommended default first.
- Build-step tolerance: none, a minifier, a full SSG.

## The brief

States the measured costs, the plan in order, the commit scopes, and a before/after measurement as the first and last steps. Get an explicit OK, then apply `prototype-checklist.md` to the changed parts.

## Measuring

- Lighthouse 13.x or later: 12.2 returns errors on the LCP-element and layout-shift audits with current Chrome, which hides what the LCP actually is.
- A local server (`python3 -m http.server`, `serve`) sends Lighthouse uncompressed files, so the local LCP is inflated. Validate the budget on the deployed site.
- Any large fetch started at boot, even in `requestIdleCallback`, counts in Lighthouse's simulated mobile LCP. Start non-critical payloads on first interaction.
