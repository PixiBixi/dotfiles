---
name: scoping-a-website
description: Use when the user asks to create, redesign, rebuild or restyle a website, landing page, portfolio, showcase site, SPA or web front end, asks for a design proposal for a site given as a URL ("propose-moi un design" plus a link), asks whether something should be a SPA, or says they are tired of their site's design ("refais mon site", "j'en ai marre du design", "fais-moi des maquettes", "surprends-moi"), or asks to optimise, speed up, lighten or fix the mobile version of an existing site whose design they keep ("vois si on peut optimiser", "le site rame", "c'est lent sur mobile", "Lighthouse"), before any mockup, prototype, measurement or code.
---

# Scoping a website

## Overview

Every pixel made before the brief exists is a guess, and each wrong guess costs a full design round. Ask the questions that change the output, write a one-page brief, get it validated, then explore. "Surprends-moi" is about the output, never a reason to skip the inputs.

## Round 0: read before asking

Silently gather what the repo, the context and any URL the user gave already answer (fetch the page, screenshot it at 375 and 1440px when a browser is available, note its content, palette, fonts and stack): existing site and its stack, build step, hosting and deploy, CSP and external-dependency policy, analytics, i18n, past design feedback in memory or project docs. Never ask a question the repo answers; state the answer in the brief instead.

For an existing live site, read `/robots.txt` and `/sitemap.xml` (and nested sitemap indexes; without one, crawl the nav and footer links). Group the URLs into page templates (home, category listing, detail, about, contact, legal) with their counts and one sample URL each. This inventory answers "number of pages" in Round 1. Note the defects it reveals (CMS sample pages, stubs, wrong headings, outdated content) under open questions in the brief.

## If the design is kept (optimisation)

When the user keeps the current design and asks to optimise it, Rounds 1 to 3 are already answered: skip them. Run Round 0 (payload sizes compressed, DOM node count, eager rendering, external dependencies), then ask one call: the target (rendering and smoothness, network weight, mobile, accessibility and SEO), the performance budget (LCP and TBT figures), and the build-step tolerance. The brief states the measured costs, the plan in order, the commit scopes, and a before/after measurement as the first and last steps. Then follow "Before showing anything" for the changed parts.

## Rounds 1 to 4: the questions

Ask with the multiple-choice question tool, at most 4 questions per call, one round per call, in the user's language. Every option is concrete (a style named with an example, a number, a real site), with a recommended default marked first. Skip a question only when Round 0 or the user already answered it.

| Round | Ask about | Why it changes the output |
|---|---|---|
| 1. Purpose | Main goal and the one action expected from a visitor; audience and their device (recruiters on desktop, clients on phone); who updates content and how often; number of pages | Architecture, CTA hierarchy, CMS or not |
| 2. Identity | What makes this person or brand unlike others: hobbies, quirks, side projects, things they collect or photograph (offer examples, invite "other"); tone (serious, warm, playful, absurd); languages; where the facts live (CV, GitHub, existing page) | The difference between a template and a site that could only be theirs |
| 3. Taste | Colour appetite (vivid, muted, dark, light, keep current palette); motion level (none, subtle, rich, playful and interactive); scroll model (classic, page by page, pinned story, horizontal); layout width (full-bleed edge to edge, centred column about 2/3 wide with a max width, or full-bleed backgrounds with centred content); sites they love and hate (ask for URLs); hard no's (sound, dark pages, gradients, emoji, specific fonts) | Kills the rounds spent discovering dislikes one at a time |
| 4. Constraints | Hosting and CSP (are CDNs allowed in prod), performance budget (LCP target, JS weight), SEO weight, accessibility target, build-step tolerance, browser support; responsive is never optional, so ask only what the mobile version may drop or simplify (heavy motion, physics, horizontal scroll) | Library choice, self-hosting, SPA or not |

Round 3 takes two calls: first colour, motion, scroll model, layout width; then sites they love and hate (asking for URLs) and hard no's, each its own question, never a footnote to another one.

Conditional: if the user says "surprends-moi", "carte blanche" or is in a hurry, ask ONE call of exactly these 4 questions, then proceed: identity hooks, tone, colour appetite plus motion level, hard no's. Outside this conditional, never merge two rounds into one call.

## Architecture verdict

State a verdict with its reason, in the brief.

| Site needs | Build it as |
|---|---|
| One page, content rarely changes, motion only | Static HTML + CSS + small vanilla or GSAP scripts |
| Several content pages, blog, galleries, SEO matters | SSG (Astro, Eleventy), zero JS by default |
| Content site with a few rich widgets (lightbox, configurator, live demo) | SSG with islands (Astro + one framework component) |
| Logged-in app state shared across views, real-time data, offline, editor-like UI | SPA (or SSR framework when SEO also matters) |

Animations, page transitions and "page by page" scrolling never justify a SPA: GSAP, View Transitions and scroll snapping work on static pages. If the user asked for a SPA and the table says otherwise, say so with the cost (first render, indexing, bundle) and let them decide.

## The brief

Write it to a file in the repo or scratchpad and get an explicit OK before any design work:

```markdown
# Brief: <site>
Goal and primary action:
Audience and devices:
Identity hooks (verified facts + personal hooks to weave in):
Tone:
Colour, motion, scroll model, layout width:
Responsive plan (what changes at 375 / 768 / 1440 / 2560px):
Page inventory (template, count, sample URL; templates to redesign):
URL plan (kept as is, or old to new 301 redirects):
Loved / hated references:
Hard no's:
Architecture verdict and why:
Constraints (hosting, CSP, perf budget, a11y, SEO, i18n):
Exploration plan (medium, number of directions):
Open questions / placeholders:
```

## Exploring

- **Medium follows the motion answer:** static canvas or images only when the question is art direction; live HTML prototypes (`preview-*.html`, noindex) as soon as motion or interaction matters.
- **Directions:** default 3, pushed fully, each built on at least one identity hook from Round 2. Offer more only if asked. Converge on one, then iterate on feedback.
- **Multi-page sites:** explore directions on the home page only. Once one direction is chosen, design every template in the inventory with real content from its sample URL, never one page per URL.
- **Facts:** every number and name comes from a source read in this session (count files, read the CV, query the API). Unknown facts become labelled placeholders such as `[CITY]`, never invented.
- **Copy:** body text is taken from the source pages. Any line Claude wrote (tagline, intro, caption) is flagged as such when the mockup is shown.
- **Images from the first prototype:** download the existing site's own photos, logo and portraits, resize them, and give every template at least one. A text-only mockup reads as cold however good the type is.
- **Warmth for a local or community site** (village, association, small shop): the header carries the real logo or emblem, the name in the display font rather than uppercase, a short greeting, and a human contact (phone plus today's opening hours). A bare uppercase name over a plain link list reads as impersonal.
- **Comparing directions on a multi-page site:** when the user keeps two directions to compare across the templates, one markup, switched by an attribute on `<html>` (`data-dir`), so content stays identical and only the design differs.
- **Mockup controls stay out of the design:** the direction switch and the theme toggle used for review live in a small floating dock, so the header being judged is the real one.
- **Real organisation:** the mockups stay local files, never published.
- **Production path:** if prod CSP forbids CDNs, plan self-hosting the libraries from the first prototype.
- **Light and dark, always, with a visible toggle:** every prototype ships both themes and a toggle button (in the review dock, see above), the choice kept in `localStorage` and applied by an inline script in `<head>` (no flash). Default to the theme the brief chose, never to `prefers-color-scheme` alone: a dark OS silently turned a "light" brief dark and the user judged the wrong version.

## Before showing anything

- Readability: body text at least 17px, contrast AA in both themes, code names legible in the display font.
- Screenshots taken in both themes, and the theme of each capture named when showing it. Headless Chrome cannot go below about 500px wide: capture 375px inside an iframe of that width.
- Not AI-looking: no generic three-card grids, glassmorphism, gradient text, purple-blue washes, emoji icons, marquees, empty voids in cards.
- Grid and flex children get `min-width: 0`: a nowrap chip row or badge otherwise widens its column past 375px.
- Checked at 375, 768, 1440 and 2560px (no horizontal scroll, readable line length on wide screens, touch targets at least 44px, no hover-only interaction), with reduced motion, and in a real browser for motion (headless screenshots freeze animations: say so instead of claiming it works).
- On a showcase or portfolio site, the hero fills the first screen (`min-height: 100svh`, content centred); a service site keeps its quick actions above the fold instead. With a full-screen hero, the next section never peeks in at load, where its scroll-triggered reveal has not fired yet and it shows as a half-hidden fragment.
- Performance, on every prototype:
  - Libraries load with `defer`, and the main script runs on `DOMContentLoaded`: a plain inline script runs before deferred libraries and silently falls back to no-motion.
  - The one or two font weights above the fold are preloaded (`<link rel="preload" as="font" crossorigin>`), self-hosted, `font-display: swap`.
  - Images have `width`, `height` and `loading="lazy"`, webp cropped to their display ratio and sized for 2x display, EXIF stripped.
  - No permanent `will-change`: each one pins a GPU layer, even when nothing moves.
  - Infinite loops (CSS keyframes, `setInterval`, `repeat: -1` tweens) pause offscreen and in hidden tabs: an IntersectionObserver per section toggles a class that sets `animation-play-state: paused`, and JS loops check it or pause their tween.
  - No CSS `transition` on `transform` for an element GSAP tweens: it lags every frame. Hover offsets go on the individual `translate`, `rotate` and `scale` properties, which compose with GSAP.

## Common mistakes

| Mistake | Fix |
|---|---|
| Asking only "which visual style?" | Identity and hard no's matter more than style labels |
| Static mockups for a user who wants motion | Ask the motion level first, prototype live |
| Dropping questions because the user is in a hurry | Use the single-call conditional above |
| Defaulting to a SPA because the user said React | Apply the verdict table, explain, let them choose |
| Inventing numbers to fill a design | Placeholders, and verify counts at the source |
| Ten shallow directions | Three deep ones, each personal |
