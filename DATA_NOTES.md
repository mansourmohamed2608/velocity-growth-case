# Data and Provider Notes

Analysis date: 15 Sep 2026. Source archive SHA-256 independently verified as `4961a25b151ca13ac56089ca46b94def6074c315445ec193c7bf87060683d35c`.

## Source files

| Brand             |                     Contacts |                                 Delta | Campaign rows / distinct | Event rows / distinct | Notes                                                  |
| ----------------- | ---------------------------: | ------------------------------------: | -----------------------: | --------------------: | ------------------------------------------------------ |
| Kilele Rides      | 83,993 / 81,215 distinct IDs | 4,180 rows; 2,500 updates + 1,680 new |                  46 / 44 |     312,000 / 303,588 | UTF-8 comma CSV; 9-row send log                        |
| Karoo Coaches     | 13,042 / 12,540 distinct IDs |                                     — |                  19 / 19 |       74,000 / 69,100 | Contacts are Windows-1252 with title-case headers      |
| Marrakech Express |       957 / 933 distinct IDs |                                     — |                    6 / 6 |             940 / 940 | UTF-8 semicolon CSV; campaign spend uses decimal comma |

Logical contact counts before validation and after applying the Kilele delta are Kilele 82,895, Karoo 12,540, and Marrakech 933. These are not displayed dashboard totals until source validation and import decisions are applied.

## Natural keys and relationships

- Contacts: `(brand, external_id)`. External contact IDs overlap across brands.
- Campaigns: `(brand, external_id)`.
- Events: `(brand, event_id)`; duplicate event rows are byte-equivalent in the supplied files.
- Imported files/runs: content SHA-256 plus brand and source kind.
- Send log: `(brand, batch_key)`.
- Provider batches: provider `batch_id`; outbound retry key is the local logical-send UUID.

All Kilele and Karoo event contact/campaign references resolve after source-key deduplication. Marrakech has 633 events referencing campaign IDs absent from its six-row campaign export; these must be rejected/audited, not silently attached. All contact references resolve.

## Deliberate quality hazards

- Kilele contacts include 2,778 duplicate-ID rows, an embedded header row, cross-brand Karoo rows, missing/invalid fields, mixed status/consent spellings, malformed emails, multiple country spellings/null tokens, and mixed timestamp formats.
- The Kilele delta overlaps 2,500 IDs and changes every overlapping record; its dated corrections take precedence over base rows.
- Karoo contacts include 502 duplicate-ID rows, 88 Kilele-branded leak rows, 46 shifted/malformed rows, CP-1252 characters, and missing values.
- Marrakech contacts include 24 duplicate-ID rows plus missing brand/status/consent values.
- Kilele campaigns contain two identical duplicate rows. Reported aggregates contain deliberate inconsistencies such as opens greater than delivered, clicks greater than opens, and sent not always equaling delivered plus bounced. These source-reported values remain labeled as reported; event-derived values are shown separately.
- Event files are not chronological. Kilele has 8,412 duplicate rows and Karoo 4,900; duplicates with the same event ID are identical. Event types are `open`, `click`, `bounce`, `unsubscribe`, and `complaint`.

## Provider contract (live docs v1.4.0)

Base URL: `https://dispatcher-production-72fc.up.railway.app`.

- Authenticate every request with `Authorization: Bearer <API_KEY>`; `X-API-Key` is also documented.
- `POST /v1/messages` accepts an optional campaign/brand and a recipients array. Recipient identity may be a string or an object keyed by `id`, `external_id`, `contact_id`, `recipient_id`, or `email`.
- Maximum 100,000 recipients per request; 600 requests/minute per key.
- `Idempotency-Key` makes a retry deliver once.
- The response contains `batch_id`, `accepted`, and `rejected`.
- `GET /v1/messages/{batch_id}/events?since=<event_id>` returns up to 1,000 events plus `next_cursor` and `has_more`.
- Documented provider event types are `delivered`, `bounced`, `opened`, and `unsubscribed`.

The provider docs call the report stream ordered and exactly-once, but the employer brief explicitly says evaluation reports will be duplicated/messy/out of order. Reconciliation therefore assumes the stricter failure model. No safe sandbox or dry-run endpoint is documented.
