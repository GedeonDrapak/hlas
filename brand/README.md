# Hlas brand kit

Podklady pro grafiku Hlasu (appka, web hlas.dev, promo video z 16. 11. 2026). Vše odpovídá aktuálnímu vzhledu appky 0.6 a webu.

## Barvy
Web hlas.dev a promo video:
| název | hex | použití |
|---|---|---|
| pozadí | `#121212` | hlavní tmavé pozadí |
| plocha 1 | `#191919` | karty, panely |
| plocha 2 | `#202020` | vnořené plochy |
| zelená Hlas | `#00E67A` | logo, akcent, koule, sloupky hlasu (jeden akcent na kompozici) |
| text | `#FAFAFA` | hlavní text na tmavé |

Appka Mac (`Sources/Hlas/DesignTokens.swift`) má o kousek jiné tóny: pozadí `#0C0D0F`, panel `#161719`, hover `#1E2023`, zelená `#00E67F` (hue 153). Ikona appky `#00E67E`. Rozdíl je okem skoro nepoznatelný, pro novou grafiku ber hodnoty webu.

Bez rámečků (borders), hloubku dělají plochy a jemné stíny.

## Písmo
- **Satoshi** (Regular, Medium, Bold) pro UI, web a běžný text. Soubory: `web/assets/fonts/` (Fontshare, zdarma i komerčně).
- **Eurostile Extended Black** jen pro velké titulky přes video (promo). Licencované písmo, není v repu, je nainstalované u Gedeona.

## Logo
`logo/`: značka je samotné „H" (jedna cesta).
- `hlas-icon-app.svg` / `-2048.png`: ikona appky (zelené H na tmavé dlaždici).
- `hlas-H-green`, `hlas-H-white`, `hlas-H-black`: samotné H, SVG + PNG 2048 s průhledností.
- Logo nekomponovat do fotek jako nalepenou vrstvu, nedeformovat, nepřebarvovat jinak než zelená / bílá / černá.

## Pilulka a koule
- `pill/hlas-pill-recording-4000.png`: pilulka při nahrávání přesně podle appky (`Sources/Hlas/OverlayPanel.swift`): kapsle výšky 40 pt, koule 20 pt, 24 sloupků hlasu, časovač. Průhledné pozadí.
- `orb/hlas-orb.png`: koule z teček (engine `web/orb.js`, thinking-orbs). Průhledné pozadí.

## Pozadí
`backgrounds/`: `day-hills.jpg` (mlžné zelené kopce, hero webu), `dusk-lake.jpg` (soumrak nad jezerem), `dusk-blurred-4k.jpg` a `dusk-soft-4k.jpg` (rozmazané varianty, jak jsou ve videu pod UI), `day-blurred.jpg`. Další fotky webu: `web/assets/` (hero, cta, karty hora / les / duny / moře).

## Snímky z proma
`stills/16x9/`: 14 klíčových snímků ve 4K z promo videa (název souboru = čas ve videu v sekundách). Samotná videa jsou na Google Drivu (`Promo hlas/v5-16x9/renders/`), ne v repu.

## Kde je co dál v repu
- Web: `web/` (zdroj `web/_src/`, build `web/_src/build.mjs`), ikony a OG obrázky `web/` + `web/assets/`.
- Appka Mac: `Sources/Hlas/` (`DesignTokens.swift` = barvy a rozměry), ikona `Resources/Brand/`.
- Windows: `windows/`.
