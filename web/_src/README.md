# hlas.dev source

The site is generated. Edit these files, never the generated `index.html` pages:

- `locales/<code>.json`: all text of the homepage in one language (40 languages). `en.json` is the master for structure.
- `build.mjs`: homepage template, language list, hreflang, schema.org, sitemap.xml, robots.txt, llms.txt.
- `pages.mjs`: content pages in Czech and English (comparison, privacy, FAQ, about, press, changelog, language hub, keyword pages).

Build: `node web/_src/build.mjs` (no dependencies). Output lands in `web/`.

Rules: no em or en dashes; Czech, Slovak and English are the only tuned languages, every other page must say so honestly; prices checked 15 November 2026.
