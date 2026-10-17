# Before showing a prototype

Each item below was a defect the user caught on a shown mockup. Checking them first saves a review round.

## Readability and look

- Body text at least 17px, contrast AA in both themes, code names legible in the display font.
- Not AI-looking: no generic three-card grids, glassmorphism, gradient text, purple-blue washes, emoji icons, marquees, empty voids in cards.
- Grid and flex children get `min-width: 0`: a nowrap chip row or badge otherwise widens its column past 375px.
- On a showcase or portfolio site, the hero fills the first screen (`min-height: 100svh`, content centred); a service site keeps its quick actions above the fold instead. With a full-screen hero, the next section never peeks in at load, where its scroll-triggered reveal has not fired yet and it shows as a half-hidden fragment.

## Screenshots

Run `scripts/screenshot.sh <url> <out-dir>`: it captures 375, 768, 1440 and 2560px in both themes and names each file after its width and theme. Name the theme of each capture when showing it.

What the script works around, for a manual capture:
- Headless Chrome cannot go below about 500px wide: 375px is captured inside an iframe of that width.
- Headless follows the OS theme: `--blink-settings=preferredColorScheme=1` for light, `--force-dark-mode --blink-settings=preferredColorScheme=0` for dark.
- A capture of a page that scrolled (deep link) comes out blank: check the scroll landing with a same-origin iframe that reads `scrollY` and the target's `getBoundingClientRect().top`, dumped with `--dump-dom`.

Also check: no horizontal scroll, readable line length on wide screens, touch targets at least 44px, no hover-only interaction, reduced motion. Headless screenshots freeze animations: check motion in a real browser, or say it was not checked instead of claiming it works.

## Performance, on every prototype

- Libraries load with `defer`, and the main script runs on `DOMContentLoaded`: a plain inline script runs before deferred libraries and silently falls back to no-motion.
- The one or two font weights above the fold are preloaded (`<link rel="preload" as="font" crossorigin>`), self-hosted, `font-display: swap`.
- Images have `width`, `height` and `loading="lazy"`, webp cropped to their display ratio and sized for 2x display, EXIF stripped.
- No permanent `will-change`: each one pins a GPU layer, even when nothing moves.
- Infinite loops (CSS keyframes, `setInterval`, `repeat: -1` tweens) pause offscreen and in hidden tabs: an IntersectionObserver per section toggles a class that sets `animation-play-state: paused`, and JS loops check it or pause their tween.
- No CSS `transition` on `transform` for an element GSAP tweens: it lags every frame. Hover offsets go on the individual `translate`, `rotate` and `scale` properties, which compose with GSAP.
