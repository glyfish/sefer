# Tiingo API — Endpoint Reference

Summary of the Tiingo end-of-day (EOD) API as used by the MCP server — meida's
`TiingoClient` and the tools built on it.

Endpoints and response fields below were **verified against the live API**;
auth details come from Tiingo's docs at
<https://www.tiingo.com/documentation/end-of-day> and
<https://www.tiingo.com/documentation/general/connecting>.

## Basics

- **Base URL:** `https://api.tiingo.com/tiingo`
- **Auth — two supported forms:**
  - Header: `Authorization: Token <YOUR_TOKEN>` ← what the client uses
  - Query param: `?token=<YOUR_TOKEN>`
- **Format:** JSON by default; `format=csv` is available on price endpoints.
- **Errors** use real HTTP status codes (404 unknown ticker, 401 bad token).
  The client wraps them as `TiingoAPIError`.
- **Rate limits are not stated in the API docs** — they are tied to your account
  tier and published on Tiingo's pricing page. Treat the free tier as
  meaningfully limited on both requests/hour and unique symbols/hour.

### Data timing and adjustments

- US equity EOD prices are typically available by **~5:30 PM EST**.
- Mutual fund NAVs post after **12 AM EST**.
- Price adjustments follow **CRSP** (Center for Research in Security Prices)
  methodology — hence the parallel `adj*` fields.

## Endpoints

Covered here is the `daily` (EOD) family, which is what this integration uses.

| Endpoint | Method | Description |
| --- | --- | --- |
| `/daily/{ticker}` | GET | Ticker metadata, including available date range |
| `/daily/{ticker}/prices` | GET | Latest EOD price (no params) or a historical range |

### Parameters for `/daily/{ticker}/prices`

| Parameter | Notes |
| --- | --- |
| `startDate` | `YYYY-MM-DD` (the docs also accept `YYYY-M-D`) |
| `endDate` | `YYYY-MM-DD` |
| `resampleFreq` | e.g. `daily`, `weekly`, `monthly`, `annually` |
| `format` | `json` (default) or `csv` |
| `columns` | Restrict returned columns |
| `sort` | Sort order (e.g. `date` / `-date`) |

**Omitting `startDate`/`endDate` returns only the latest single datapoint** —
not the full history. A range is required for a time series.

Tiingo also offers IEX (intraday), news, crypto, forex, and fundamentals APIs
under other path prefixes. None are wrapped by this integration.

## Response shapes

Unlike FRED and BLS, Tiingo has **no response envelope**.

**`/daily/{ticker}`** returns a single JSON **object** (verified live):

```json
{
  "ticker": "AAPL",
  "name": "Apple Inc",
  "description": "Apple Inc. designs, manufactures...",
  "startDate": "1980-12-12",
  "endDate": "2026-07-17",
  "exchangeCode": "NASDAQ"
}
```

**`/daily/{ticker}/prices`** returns a bare JSON **array** of rows (verified live):

```json
[
  {
    "date": "2024-01-02T00:00:00.000Z",
    "open": 187.15, "high": 188.44, "low": 183.885, "close": 185.64,
    "volume": 82488200,
    "adjOpen": 186.06, "adjHigh": 187.34, "adjLow": 182.81, "adjClose": 184.56,
    "adjVolume": 82488200,
    "divCash": 0.0, "splitFactor": 1.0
  }
]
```

### Gotchas

- **The prices endpoint returns a top-level array**, so there is no `status` or
  `count` to inspect. The client wraps it into a `TiingoPriceSeries` so callers
  get a consistent object with the ticker attached.
- **`date` is a full ISO-8601 timestamp with a `Z` suffix** (`2024-01-02T00:00:00.000Z`),
  not a plain date, even though these are daily bars.
- **Fields are camelCase** (`adjClose`, `divCash`, `splitFactor`, `exchangeCode`).
  The client models bind them to snake_case attributes but keep the vendor
  spelling as the pydantic **alias** — which is what a published schema would
  emit, hence the separate response models below.
- **Always prefer the `adj*` fields** for analysis — the raw `open/high/low/close`
  are unadjusted for splits and dividends.
- **Ticker lookups are case-insensitive and echoed upper-case** — querying
  `/daily/aapl` returns `"ticker": "AAPL"` (verified). The client additionally
  upper-cases `TiingoPriceSeries.ticker`, since the prices endpoint returns no
  ticker of its own.

## What the integration wraps

`TiingoClient` (`clients/tiingo.py`) covers both daily endpoints. The client and
its models are **meida's** — they sat in `navi/lib/clients` until it was clear
meida was their only consumer; they still import navi's `lib.env` for the token
and base URL.

| Client method | Endpoint | MCP tool |
| --- | --- | --- |
| `get_meta` | `/daily/{ticker}` | `tiingo_series_info` |
| `get_prices` | `/daily/{ticker}/prices` | `tiingo_price_series` |

`get_prices` assembles `startDate`/`endDate`/`resampleFreq` only when provided,
and upper-cases the ticker on the returned series.

Typed models live in `clients/models/tiingo.py`: `TiingoMeta`,
`TiingoPrice`, `TiingoPriceSeries` — frozen, with camelCase aliases.

## What the tools publish

Tiingo's leakage is pure naming. There is no envelope to strip and nothing to
flatten — but the client models carry a vendor alias on almost every field, and
pydantic publishes a field under its alias, so returning them from a tool would
put `exchangeCode`, `startDate`, `adjClose`, `divCash` and `splitFactor` into
this server's schema, beside the snake_case that every other tool here uses.
`mcp_server/responses/tiingo.py` is the published layer that fixes it:
`TiingoSeriesInfo`, `TiingoPriceRow`, `TiingoPriceSeries`, alias-free.

| Wire / client alias | Published |
| --- | --- |
| `exchangeCode` | `exchange_code` |
| `startDate`, `endDate` | `start_date`, `end_date` |
| `adjOpen`, `adjHigh`, `adjLow`, `adjClose`, `adjVolume` | `adj_open`, `adj_high`, `adj_low`, `adj_close`, `adj_volume` |
| `divCash` | `div_cash` |
| `splitFactor` | `split_factor` |

Three further decisions:

- **Dates become ISO `YYYY-MM-DD` strings.** The client parses a price row's
  `2024-01-03T00:00:00.000Z` into a `datetime`; the response layer drops the
  time, because an end-of-day feed timestamps every row at midnight UTC — the
  time carries no information and only makes the field harder to join on.
  Unparseable input yields `null` rather than a date-shaped field that is not a
  date; the row is still published with its prices.
- **A price row keeps its whole body.** Tiingo is the one source here whose
  observation is not a single number — a trading day is OHLCV plus its
  split/dividend-adjusted twin — so the row is not collapsed to the house
  `{date, value}` pair. It still carries `date` in the same ISO form as every
  other source, so a price series aligns with a FRED or BLS series without
  special-casing.
- **`count` is what Tiingo sent, not what was mapped.** A null row is skipped
  defensively, and counting the survivors would make that loss undetectable by
  agreeing with the list it had just shortened. `count != len(prices)` therefore
  means rows were dropped in translation.

| Tool | Model | Top-level fields |
| --- | --- | --- |
| `tiingo_series_info` | `TiingoSeriesInfo` | `ticker`, `name`, `exchange_code`, `start_date`, `end_date`, `description` |
| `tiingo_price_series` | `TiingoPriceSeries` | `ticker`, `count`, `prices` |

`from_tiingo_meta` and `from_tiingo_price_series` are pure: no I/O, and a `None`
payload maps to an empty record rather than `None`, which the tool boundary
could not serialize. Tests: `tests/test_responses_tiingo.py`.

Both shapes are visible side by side in the notebooks:
`notebooks/tiingo/client.ipynb` drives `TiingoClient` directly (the parsing
models), while `mcp.ipynb` and `walkthrough.ipynb` go through the server (the
published models).

## Configuration note

The environment variables are `TIINGO_API_KEY` and `TIINGO_BASE_URL` (in
`navi/.env`). These were previously misspelled `TINGO_*`; the spelling was
corrected — if you have another checkout or shell environment still exporting
the old names, update it.
