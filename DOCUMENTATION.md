# Task 6 — Random User Generator

All data is produced by SQL stored functions inside PostgreSQL.
Python only renders HTML and reads the result of `generate_users()`.

## Schema

One dictionary table serves every locale; the locale is a column, not a
separate table per language, so adding a language is only a set of `INSERT`s.

```sql
names(locale, kind, idx, value)     -- PRIMARY KEY (locale, kind, idx)
dict_size(locale, kind, n)          -- number of entries per (locale, kind)
```

`kind` is one of: `first_male`, `first_female`, `last`, `title_male`,
`title_female`, `suffix`, `street`, `city`, `region`, `eye_color`,
`email_domain`.

`dict_size` exists so that picking a value is one indexed lookup instead of
a `count(*)` over the dictionary on every call.

### Dictionary capacity

| locale | first names | last | street | city |
|---|---|---|---|---|
| en_US | 703 | 1000 | 1200 | 800 |
| de_DE | 2002 | 404 | 1200 | 392 |

Distinct combinations of name × surname × street × city:
**6.7 × 10¹¹** for en_US and **3.8 × 10¹¹** for de_DE, far beyond the
required 100 000 – 1 000 000 users.

## Reproducibility

`random()` is never used: it returns a different value on every call, so the
same seed could not reproduce the same user.

Instead every value is derived from an MD5 hash of a key built from
`seed | locale | page | index | field`. The same inputs therefore always
produce the same output, different fields of one user are independent, and
no state has to be stored between requests.

## Functions

### `rnd(key text) -> double precision`
Uniform value in `[0, 1)`.
Takes the first 13 hex digits of `md5(key)`, casts them to a 52-bit integer
and divides by 2⁵². 52 bits is the mantissa width of `double precision`, so
every representable value in the range can occur.

### `ukey(seed, locale, page, idx, field) -> text`
Builds the key of one field of one user by joining its parts with `|`.

### `rnd_int(key, lo, hi) -> int`
Uniform integer in `[lo, hi]`: `lo + floor(rnd(key) * (hi - lo + 1))`.

### `rnd_bool(key, p) -> boolean`
True with probability `p`. Used for optional parts such as a title.

### `rnd_normal(key, mean, sd) -> double precision`
Normal distribution via the **Box–Muller transform**: two independent
uniforms `u1`, `u2` give `mean + sd · √(−2 ln u1) · cos(2π u2)`.
Measured over 50 000 users: mean 172.02 and sd 8.97 against the requested
172 and 9.

### `rnd_lat(key)`, `rnd_lon(key)`
A point distributed **uniformly over the sphere**, which is not the same as
two uniform angles: a band of latitude near the equator covers more surface
than one of the same width near a pole, so uniform latitude would crowd the
poles. Longitude is uniform in `[−180, 180)`, latitude is
`asin(2u − 1)` in degrees. Measured: 13.14 % of points above 60° latitude
against the theoretical 13.40 %.

### `rnd_pick(locale, kind, key) -> text`
One dictionary value: `idx = floor(rnd(key) · n)`, then a primary-key lookup.

### `fill_digits(mask, key) -> text`
Replaces every `#` in a mask with a digit, each from its own key. Used for
phone numbers and postal codes.

### `gen_sex(key) -> text`
Chosen once per user and reused, so the title, the first name and the middle
name agree with each other.

### `gen_first(locale, sex, key)`, `gen_last(locale, key)`
A single dictionary lookup each. Kept separate so that `gen_email` can use
the real names rather than parsing them back out of the full name.

### `gen_name(locale, sex, first, last, key) -> text`
Assembles the full name. Optional parts: a title (25 %), a middle name
(35 %) and a suffix (8 %).

### `gen_address(locale, key) -> text`
Words come from the locale, the layout follows the local convention:

* `en_US` — `[Apt. N, ] house street, city, region ZIP`
* `de_DE` — `street house[/apartment], ZIP city`

### `gen_phone(locale, key) -> text`
Three formats per locale, chosen by the key:
`(###) ###-####`, `###-###-####`, `+1-###-###-####` for en_US;
`+49 ### #######`, `0### ########`, `(0###) ######` for de_DE.

### `gen_email(locale, first, last, key) -> text`
Three shapes: `first.last@`, `flast@`, `last<number>@`. Non-alphanumeric
characters are stripped, so umlauts in German names do not break the address.

### `generate_users(locale, seed, page, count) -> table`
The entry point. Returns `count` rows; the same `(locale, seed, page)`
always returns the same rows. `row_no` is continuous across pages:
`(page − 1) · count + i`.

## Benchmark

Measured locally, best of three runs:

| users | seconds | users/sec |
|---|---|---|
| 1 000 | 0.00 | 458 803 |
| 10 000 | 0.01 | 1 889 779 |
| 50 000 | 0.01 | 3 830 867 |
| 100 000 | 0.03 | 2 881 449 |

Small batches are dominated by connection overhead; throughput settles
around **three million users per second**.

Reproduce with `DATABASE_URL=... python benchmark.py`.

## Install

```bash
psql "$DATABASE_URL" -f 01_schema.sql
psql "$DATABASE_URL" -f 02_functions.sql
pip install -r requirements.txt
python app.py
```

## Adding a locale

Insert rows into `names` with the new locale code, refresh `dict_size`, and
add the code to `LOCALES` in `app.py`. No schema change and no new table.
