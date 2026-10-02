---
name: amazon-flipkart-scraping
description: When the user wants product listings, prices, ratings, or a price comparison scraped from Amazon.in or Flipkart.com. Use for "scrape Amazon", "scrape Flipkart", "search monitors/laptops/phones on Amazon India", "compare prices on Flipkart vs Amazon", "get product listings from Indian marketplaces", "pull ASINs/PIDs", or any request to collect catalogue data from amazon.in or flipkart.com. Covers search-result extraction, product-detail pages, pagination, and cross-site matching.
metadata:
  version: 1.0.0
---

# Amazon.in + Flipkart listing scraper

Both sites render client-side and both ship hashed, per-deploy CSS class names. **Hardcoding a Flipkart class like `.lvJbLV` works until the next deploy breaks it.** Everything below anchors on stable semantics instead: `data-asin`, `href` patterns, the `title` attribute, and childless text nodes.

## Rules

1. **Use a real browser tab, not `read`/`fetch`/curl.** Both SPAs hydrate after load; static fetches return skeleton HTML. Amazon's bot check also trips on plain HTTP.
2. **Never hardcode hashed class names.** Amazon changes them by experiment; Flipkart ships a new hash per deploy. Use the selectors in this file — they are attribute- and text-anchored and have survived repeated runs.
3. **Verify before reporting.** Print extracted rows to the caller. Never report a count or a price you did not observe in the page.
4. **State the caveats you observed** (ad slots present, geo-specific delivery, results that don't actually match the query).

## Amazon.in

### Search results

URL: `https://www.amazon.in/s?k=<query+with+pluses>`, next page `&page=2`.

Card root is the one stable handle — `data-component-type="s-search-result"` — plus `data-asin` for the key.

```js
const cards = [...document.querySelectorAll('div[data-component-type="s-search-result"]')].map(c => {
  const asin = c.getAttribute('data-asin');
  return {
    asin,
    title: c.querySelector('h2')?.innerText.trim() || null,
    // rebuild the URL: sponsored cards only expose /sspa/click redirects
    url: `https://www.amazon.in/dp/${asin}`,
    price: c.querySelector('.a-price .a-offscreen')?.textContent || null,
    mrp: c.querySelector('.a-price.a-text-price .a-offscreen')?.textContent || null,
    rating: c.querySelector('.a-icon-alt')?.textContent || null,   // "4.1 out of 5 stars"
    reviews: (c.innerText.match(/\(([\d,]+)\)/) || [])[1] || null,
    delivery: c.querySelector('.udm-primary-delivery-message')?.innerText || null,
    badges: [...c.querySelectorAll('.a-badge-text')].map(b => b.innerText.trim()),
    sponsored: !!c.querySelector('[data-component-type="sp-sponsored-label"], .puis-sponsored-label-text')
  };
});
```

- `.a-price .a-offscreen` and `.a-badge-text` are stable Amazon primitives, not hashed.
- Expect ~6 sponsored cards in the first screen. Rank on `price` only after filtering `sponsored` out, or the cheapest row is an ad.

### Product detail page

```js
({
  title: document.querySelector('#productTitle')?.innerText.trim(),
  price: document.querySelector('.a-price .a-offscreen')?.textContent,
  mrp: document.querySelector('.a-price.a-text-price .a-offscreen')?.textContent,
  rating: document.querySelector('#acrPopover')?.getAttribute('title') || document.querySelector('.a-icon-alt')?.textContent,
  availability: document.querySelector('#availability')?.innerText.trim(),
  highlights: [...document.querySelectorAll('#feature-bullets li span.a-list-item')]
    .map(s => s.innerText.trim()).filter(Boolean)
})
```

**Spec table — the key is the *first* cell, not a `<th>`.** Rows are `td.a-span3` (label) + `td.a-span9` (value). Selecting `th` returns the label as its own value; select all cells and index 0 is the label.

```js
const specs = {};
for (const r of document.querySelectorAll(
  '#productOverview_feature_div tr, #productDetails_techSpec_section_1 tr, ' +
  '#productDetails_techSpec_section_2 tr, #productDetails_detailBullets_sections1 tr, ' +
  '#detailBullets_feature_div li'
)) {
  const cells = [...r.querySelectorAll('td, th')].map(c => c.innerText.trim());
  if (cells.length >= 2 && cells[0]) specs[cells[0].replace(/[‎‏]/g, '')] = cells.slice(1).join(' ').replace(/\s+/g, ' ').slice(0, 120);
  else if (cells.length === 1 && cells[0].includes(':')) {
    const [k, ...v] = cells[0].split(':');
    specs[k.trim()] = v.join(':').trim().slice(0, 120);
  }
}
```

Caveat: `#productOverview_feature_div` often carries only 4–5 rows (Brand, Screen Size, Resolution, Aspect Ratio, Surface). The full table may be absent or collapsed; a thin spec map is normal, not a parser bug.

## Flipkart.com

### Search results

URL: `https://www.flipkart.com/search?q=<urlencoded query>`, next page `&page=2`.

There is no stable card root. Anchor on title links and climb to the nearest ancestor that contains a price — a card is the smallest ancestor holding one product.

```js
const lines = el => (el.innerText || '').split('\n').map(s => s.trim()).filter(Boolean);
const leaves = (root, re) => [...root.querySelectorAll('*')]
  .filter(e => e.children.length === 0 && re.test(e.textContent.trim()))
  .map(e => e.textContent.trim());

const seen = new Set(), out = [];
for (const a of document.querySelectorAll('a[title][href*="/p/itm"]')) {
  const url = a.href.split('?')[0];
  if (seen.has(url)) continue;
  seen.add(url);

  let card = a;
  for (let i = 0; i < 6 && card && !/₹/.test(card.innerText || ''); i++) card = card.parentElement;
  if (!card) continue;

  const L = lines(card);
  const money = leaves(card, /^₹/).filter(p => p.length <= 12);   // <-- leaf nodes, not card.innerText
  out.push({
    title: a.getAttribute('title'),        // full, untruncated title
    url,
    pid: (a.href.match(/pid=([A-Z0-9]+)/) || [])[1] || null,       // review-aggregation id
    subtitle: L.find(s => !/₹|%|\(.*\)|^[₹\d,.]+$/.test(s) && s !== a.innerText && s.length > 5) || null,
    // rating comes from the line, NOT from leaves — the "4.4" node has an icon child,
    // so only the count "(219)" is a childless leaf. Leaf-matching on the rating yields null.
    ...(() => { const m = (L.find(s => /^[\d.]+\s*\(/.test(s)) || '').match(/^([\d.]+)\s*\(?\s*([\d,.]+\s*[kK]?)/); return { rating: m ? m[1] : null, reviews: m ? m[2].replace(/\s/g, '') : null }; })(),
    price: money[0] || null,
    mrp: money[1] || null,
    off: leaves(card, /%/).find(s => /off/i.test(s)) || null,
    offers: L.filter(s => /off on exchange|No cost EMI|bank offer/i.test(s)),
    stock: L.find(s => /Only \d+ left|Only few left/i.test(s)) || null
  });
}
```

**The price-parsing trap:** `card.innerText` concatenates adjacent nodes into `₹11,999₹16,00025% off`. Any regex over that string — splitting on `% off`, or `\(([\d,]+)\)` — yields `mrp: "₹16,"` / `off: "00025%"`. Prices must come from **childless leaf nodes** (`children.length === 0`), where each node is one clean value. Same trap produces garbage review counts.

Total matches: `(document.body.innerText.match(/Showing\s+(\d+)\s*–\s*(\d+)\s*of\s*([\d,]+)/) || [])`.

### Product detail page

Title, breadcrumb, and buy-box price extract fine. **The spec table is not in the DOM pre-login.** It is fetched lazily; scrolling the window, scrolling inner containers, and clicking the "Specifications" tab all leave `General Features` absent. Do not spend turns retrying.

- Extract what's there (title, price leaf nodes, breadcrumb, Key Highlights).
- For real specs: use a logged-in session (`browser.open({ app: { relay: true } })` drives the user's real Chrome), or pull specs from the listing-page subtitle and the title string.
- Leave `null` and say the specs were gated. Never invent spec values.

## Workflow

```js
const grab = async (name, url) => {
  const t = await browser.open({ name, url, wait_until: "domcontentloaded", timeout: 60 });
  await new Promise(r => setTimeout(r, 2000));   // let cards hydrate
  return t;
};
const amz = await grab("amz", "https://www.amazon.in/s?k=qhd+ips+monitor");
// ... run the Amazon snippet via amz.evaluate(...)
```

- `wait_until: "domcontentloaded"` + a 2s settle is enough; a full `networkidle0` hangs on both sites' long-poll connections.
- Extract in the page with `tab.evaluate(fn)`, return plain JSON, aggregate in the kernel.
- Close tabs when done: `await browser.close({ all: true })`.
- If Amazon returns the "make sure you're not a robot" page, stop and report it — do not rotate user agents or proxies.

## Cross-site matching

Match on a model number, not a title. Flipkart titles end in a parenthesised model code (`27U631A-BD.CTRDMR`); Amazon buries it mid-title. Pull `pid`, then look for the alphanumeric model token shared by both titles.

Ratings are **separate review pools** — the same SKU rated 4.4★/219 on Flipkart and 4.1★/140 on Amazon. Report both; never average them.

## Known noise

- Relevance search returns off-spec products. Filter client-side, e.g. QHD-IPS: `/2560\s*[x×]\s*1440|\bQHD\b|Quad HD|WQHD|\b2K\b/i` **and** `/\bIPS\b/i` (typical yield: ~half of rows).
- A handful of cards per page (2–4) render no rating at all — new or unrated listings. `null` is correct there, not a parser failure.
- Amazon `delivery` text is pincode-specific ("Delivering to Coimbatore 641012"). Record the location the tab resolved to; prices and ETAs shift by geography.
- Promotional pricing is live-at-fetch and expires; stamp results with a fetch time.

## Related

- For a broader marketplace sweep, mirror this structure: browser tab, semantic anchors, client-side filtering, honest nulls.
