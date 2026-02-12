# Appfigures — App Store Analytics API

REST API at `https://api.appfigures.com/v2/`. Data for NimbleBit's full portfolio:
downloads, revenue, ratings, reviews, and rankings across Apple App Store and Google Play.

## Auth

Two env vars in `.env`:
- `APPFIGURES_TOKEN` — Personal access token (`pat_...`)
- `APPFIGURES_CLIENT_KEY` — API client key

Every request needs both headers:
```bash
-H "Authorization: Bearer $APPFIGURES_TOKEN" -H "X-Client-Key: $APPFIGURES_CLIENT_KEY"
```

Load env vars before calling:
```bash
export $(grep 'APPFIGURES' /Users/ceres/discoclaw/.env | xargs)
```

## Quick Reference

```bash
# Base setup (run once per shell)
export $(grep 'APPFIGURES' /Users/ceres/discoclaw/.env | xargs)
AF="curl -s -H \"Authorization: Bearer $APPFIGURES_TOKEN\" -H \"X-Client-Key: $APPFIGURES_CLIENT_KEY\""
BASE="https://api.appfigures.com/v2"
```

## Key Product IDs (Apps Only)

| Game | Apple ID | Google Play ID |
|------|----------|----------------|
| Pocket Frogs | 6293456 | 280329864376 |
| Pocket Planes | 212280778 | 334474379517 |
| Pocket Trains | 36570540245 | 36134072219 |
| Pocket Trucks | 337102257565 | 337089023621 |
| Tiny Tower | 6543700 | 190839415791 |
| Tiny Tower Classic | 338130294207 | — |
| Tiny Tower Vegas | 40182286179 | 40163732446 |
| Bit City | 280101630582 | 276259749908 |
| Sky Burger | 5897157 | 214121192 |
| Disco Zoo | 39892812947 | 39987833231 |
| LEGO Tower | 281346644645 | 281289944467 |
| Pixel Shelter | 338339529151 | 338170283215 |
| Capitals | 337419974910 | — |

Use comma-separated IDs to query multiple: `products=6293456,280329864376`

## Endpoints

### Products

```bash
# All your products (apps + IAPs)
curl ... "$BASE/products/mine?pretty=true"

# Filter by store: apple, google_play
curl ... "$BASE/products/mine?store=apple&pretty=true"

# Search any product
curl ... "$BASE/products/search?term=pocket+frogs&pretty=true"
```

Response is an object keyed by product ID. Each product has: `id`, `name`, `developer`,
`store`, `type` (app/inapp), `active`, `version`, `release_date`, `accessible_features`.

### Sales Reports

```bash
# Total sales for specific products, last 7 days
curl ... "$BASE/reports/sales?group_by=products&start_date=-7d&end_date=today&products=6293456&pretty=true"

# Daily breakdown
curl ... "$BASE/reports/sales?group_by=dates&start_date=-7d&end_date=today&products=6293456&granularity=daily&pretty=true"

# By product and date
curl ... "$BASE/reports/sales?group_by=products,dates&start_date=-30d&end_date=today&granularity=daily&products=6293456&pretty=true"

# By country
curl ... "$BASE/reports/sales?group_by=countries&start_date=-7d&end_date=today&products=6293456&pretty=true"

# Include IAP sales
curl ... "$BASE/reports/sales?group_by=products&start_date=-7d&include_inapps=true&products=6293456&pretty=true"
```

**Parameters:**
- `group_by` — `products`, `dates`, `countries`, `stores` (comma-separated combos)
- `start_date` / `end_date` — `YYYY-MM-DD` or relative (`-7d`, `-1m`, `-6m`, `today`)
- `granularity` — `daily`, `weekly`, `monthly`
- `products` — comma-separated product IDs
- `countries` — comma-separated ISO codes (`US,GB,JP`)
- `include_inapps` — `true`/`false`
- `dataset` — `financial` (default) or other
- `format` — `json` (default) or `csv`

**Response fields:** `downloads`, `re_downloads`, `uninstalls`, `updates`, `net_downloads`,
`revenue`, `returns`, `promos`, `gifts`, `edu_downloads`, `iap_amount`, `iap_revenue`,
`subscription_purchases`, `subscription_revenue`, etc.

### Revenue Reports

```bash
# Revenue by product, last 7 days
curl ... "$BASE/reports/revenue?group_by=products&start_date=-7d&end_date=today&products=6293456&pretty=true"

# Revenue over time
curl ... "$BASE/reports/revenue?group_by=dates&start_date=-30d&end_date=today&granularity=daily&products=6293456&pretty=true"
```

Same parameters as sales. Revenue response breaks down by source:
`sales`, `iap`, `ads`, `subscriptions`, `returns`, `edu`, `total`,
plus `gross_*` variants (before store commission).

### Reviews

```bash
# Recent reviews for a product
curl ... "$BASE/reviews?products=6293456&count=10&pretty=true"

# Filter by stars
curl ... "$BASE/reviews?products=6293456&stars=1&count=10&pretty=true"

# Search reviews
curl ... "$BASE/reviews?products=6293456&q=crash&count=10&pretty=true"

# Translate reviews to English
curl ... "$BASE/reviews?products=6293456&count=10&lang=en&pretty=true"

# Review counts
curl ... "$BASE/reviews/count?products=6293456&pretty=true"

# Page through results
curl ... "$BASE/reviews?products=6293456&count=25&page=2&pretty=true"
```

**Parameters:**
- `products` — comma-separated product IDs
- `count` — results per page (default 25)
- `page` — page number
- `stars` — filter by star rating (1-5)
- `q` — search text in reviews
- `lang` — translate to ISO language code
- `sort` — sort order
- `countries` — filter by country ISO codes

**Response:** `{ total, pages, this_page, reviews: [...] }` where each review has:
`author`, `title`, `review`, `stars`, `iso`, `version`, `date`, `store`, `product_name`.

### Ratings

```bash
# Current ratings by product
curl ... "$BASE/reports/ratings?group_by=products&products=6293456&pretty=true"

# Ratings over time
curl ... "$BASE/reports/ratings?group_by=products,dates&start_date=-30d&end_date=today&granularity=daily&products=6293456&pretty=true"

# By country
curl ... "$BASE/reports/ratings?group_by=products,countries&products=6293456&pretty=true"
```

**Response fields:** `breakdown` (array of [1-star, 2-star, 3-star, 4-star, 5-star] counts),
`average`, `total`, `positive`, `negative`, `neutral`, plus `new_*` variants for the period.

### Rankings

```bash
# Rank history for a product
curl ... "$BASE/ranks/6293456/daily/-7d/today?pretty=true"

# Multiple products
curl ... "$BASE/ranks/6293456,280329864376/daily/-7d/today?pretty=true"

# Filter by country
curl ... "$BASE/ranks/6293456/daily/-7d/today?countries=US&pretty=true"

# Category snapshot (top N in a category)
curl ... "$BASE/ranks/snapshots/today/US/6014?top=100&pretty=true"
```

**Rank path format:** `/ranks/{product_ids}/{granularity}/{start_date}/{end_date}`
- `granularity` — `daily`, `weekly`
- `countries` — query param, comma-separated ISO codes

## Common Recipes

```bash
# "How did Pocket Frogs do last week?" (both stores)
curl ... "$BASE/reports/sales?group_by=products&start_date=-7d&products=6293456,280329864376&pretty=true"
curl ... "$BASE/reports/revenue?group_by=products&start_date=-7d&products=6293456,280329864376&pretty=true"

# "Show me recent 1-star reviews for Pocket Planes"
curl ... "$BASE/reviews?products=212280778,334474379517&stars=1&count=10&pretty=true"

# "Revenue trend for Tiny Tower this month"
curl ... "$BASE/reports/revenue?group_by=dates&start_date=-30d&granularity=daily&products=6543700,190839415791&pretty=true"

# "Portfolio overview last 7 days" (all apps — omit products param)
curl ... "$BASE/reports/revenue?group_by=products&start_date=-7d&pretty=true"
```

## Platform Aggregation

**Combine platforms by default.** When reporting on a game, sum the Apple and Google Play
results into a single total unless the user specifically asks for a per-platform breakdown.
Always query both platform IDs (e.g., `products=6293456,280329864376` for Pocket Frogs).

If the user asks to "split by platform" or "break down by store," use `group_by=products`
(or add `stores` to the group_by) so each platform's numbers appear separately.

## Notes

- All dates in responses are ISO 8601 format
- Revenue amounts are strings (e.g., `"3912.01"`) — parse as floats
- The `gross_*` fields are pre-commission; regular fields are net (after store cut)
- Product IDs are numeric but may be returned as string keys in JSON objects
- Add `&pretty=true` for human-readable output; omit for compact JSON
- Rate limits exist but are generous for personal access tokens
