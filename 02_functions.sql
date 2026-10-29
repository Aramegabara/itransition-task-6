CREATE OR REPLACE FUNCTION rnd(key text)
RETURNS double precision AS $$
    SELECT ('x' || substr(md5(key), 1, 13))::bit(52)::bigint::double precision
           / 4503599627370496.0;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION ukey(seed text, locale text, page int, idx int, field text)
RETURNS text AS $$
    SELECT seed || '|' || locale || '|' || page || '|' || idx || '|' || field;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_int(key text, lo int, hi int)
RETURNS int AS $$
    SELECT lo + floor(rnd(key) * (hi - lo + 1))::int;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_bool(key text, p double precision)
RETURNS boolean AS $$
    SELECT rnd(key) < p;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_normal(key text, mean double precision, sd double precision)
RETURNS double precision AS $$
    SELECT mean + sd * sqrt(-2 * ln(greatest(rnd(key || '#u1'), 1e-12)))
                * cos(2 * pi() * rnd(key || '#u2'));
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_lat(key text)
RETURNS double precision AS $$
    SELECT round(degrees(asin(2 * rnd(key || '#lat') - 1))::numeric, 6)::double precision;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_lon(key text)
RETURNS double precision AS $$
    SELECT round((360 * rnd(key || '#lon') - 180)::numeric, 6)::double precision;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION rnd_pick(p_locale text, p_kind text, key text)
RETURNS text AS $$
    SELECT n.value
    FROM dict_size d
    JOIN names n
      ON n.locale = d.locale AND n.kind = d.kind
     AND n.idx = floor(rnd(key) * d.n)::int
    WHERE d.locale = p_locale AND d.kind = p_kind;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fill_digits(mask text, key text)
RETURNS text AS $$
    SELECT string_agg(
               CASE WHEN ch = '#' THEN rnd_int(key || '#d' || i, 0, 9)::text ELSE ch END,
               '' ORDER BY i)
    FROM regexp_split_to_table(mask, '') WITH ORDINALITY AS t(ch, i);
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION gen_sex(key text)
RETURNS text AS $$
    SELECT CASE WHEN rnd_bool(key || '#sex', 0.5) THEN 'male' ELSE 'female' END;
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION gen_first(p_locale text, p_sex text, key text)
RETURNS text AS $$
    SELECT rnd_pick(p_locale, 'first_' || p_sex, key);
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION gen_last(p_locale text, key text)
RETURNS text AS $$
    SELECT rnd_pick(p_locale, 'last', key || '#last');
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION gen_name(p_locale text, p_sex text,
                                    p_first text, p_last text, key text)
RETURNS text AS $$
    SELECT trim(concat_ws(' ',
        CASE WHEN rnd_bool(key || '#has_title', 0.25)
             THEN rnd_pick(p_locale, 'title_' || p_sex, key || '#title') END,
        p_first,
        CASE WHEN rnd_bool(key || '#has_middle', 0.35)
             THEN gen_first(p_locale, p_sex, key || '#middle') END,
        p_last,
        CASE WHEN rnd_bool(key || '#has_suffix', 0.08)
             THEN rnd_pick(p_locale, 'suffix', key || '#suffix') END));
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION gen_address(p_locale text, key text)
RETURNS text AS $$
    SELECT CASE
        WHEN p_locale = 'de_DE' THEN
            rnd_pick(p_locale, 'street', key || '#street') || ' ' ||
            rnd_int(key || '#house', 1, 199)::text ||
            CASE WHEN rnd_bool(key || '#apt', 0.3)
                 THEN '/' || rnd_int(key || '#aptno', 1, 40)::text ELSE '' END ||
            ', ' || fill_digits('#####', key || '#zip') || ' ' ||
            rnd_pick(p_locale, 'city', key || '#city')
        ELSE
            CASE WHEN rnd_bool(key || '#apt', 0.3)
                 THEN 'Apt. ' || rnd_int(key || '#aptno', 1, 400)::text || ', ' ELSE '' END ||
            rnd_int(key || '#house', 1, 9999)::text || ' ' ||
            rnd_pick(p_locale, 'street', key || '#street') || ', ' ||
            rnd_pick(p_locale, 'city', key || '#city') || ', ' ||
            rnd_pick(p_locale, 'region', key || '#region') || ' ' ||
            fill_digits('#####', key || '#zip')
    END;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION gen_phone(p_locale text, key text)
RETURNS text AS $$
    SELECT fill_digits(
        (ARRAY[
            CASE WHEN p_locale = 'de_DE' THEN '+49 ### #######' ELSE '(###) ###-####' END,
            CASE WHEN p_locale = 'de_DE' THEN '0### ########'   ELSE '###-###-####'   END,
            CASE WHEN p_locale = 'de_DE' THEN '(0###) ######'   ELSE '+1-###-###-####' END
        ])[rnd_int(key || '#pformat', 1, 3)], key || '#phone');
$$ LANGUAGE sql IMMUTABLE;

CREATE OR REPLACE FUNCTION gen_email(p_locale text, p_first text, p_last text, key text)
RETURNS text AS $$
    SELECT lower(regexp_replace(
        CASE rnd_int(key || '#eformat', 1, 3)
            WHEN 1 THEN p_first || '.' || p_last
            WHEN 2 THEN substr(p_first, 1, 1) || p_last
            ELSE p_last || rnd_int(key || '#enum', 1, 99)::text
        END, '[^a-zA-Z0-9._]', '', 'g')
        || '@' || rnd_pick(p_locale, 'email_domain', key || '#domain'));
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION generate_users(
    p_locale text,
    p_seed   text,
    p_page   int,
    p_count  int DEFAULT 10)
RETURNS TABLE (
    row_no    int,
    full_name text,
    address   text,
    latitude  double precision,
    longitude double precision,
    height_cm numeric,
    weight_kg numeric,
    eye_color text,
    phone     text,
    email     text
) AS $$
    SELECT
        (p_page - 1) * p_count + i                            AS row_no,
        gen_name(p_locale, sx, fn, ln, k)                     AS full_name,
        gen_address(p_locale, k)                              AS address,
        rnd_lat(k)                                            AS latitude,
        rnd_lon(k)                                            AS longitude,
        round(rnd_normal(k || '#height', 172, 9)::numeric, 1) AS height_cm,
        round(rnd_normal(k || '#weight', 75, 13)::numeric, 1) AS weight_kg,
        rnd_pick(p_locale, 'eye_color', k || '#eye')          AS eye_color,
        gen_phone(p_locale, k)                                AS phone,
        gen_email(p_locale, fn, ln, k)                        AS email
    FROM generate_series(1, p_count) AS i,
         LATERAL (SELECT ukey(p_seed, p_locale, p_page, i, 'user') AS k) AS a,
         LATERAL (SELECT gen_sex(a.k) AS sx) AS b,
         LATERAL (SELECT gen_first(p_locale, b.sx, a.k || '#first') AS fn,
                         gen_last(p_locale, a.k) AS ln) AS c
    ORDER BY i;
$$ LANGUAGE sql STABLE;
