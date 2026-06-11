-- Panelist city normalization
-- ---------------------------------------------------------------------------
-- The "city" of a record was modelled twice across the schema: as a normalized
-- FK (city_id -> cities.id) and as free text (address_city / city_name). The
-- text was used as the de-facto join key, which is fragile because cities.name
-- was not even unique. This migration anchors the panelist's residence city to
-- the account's city catalog (cities) via city_id, keeping address_city only as
-- an optional free-text detail (locality / neighbourhood).
--
-- Scope: panelists only. ETL tables (journeys, one_db, processed_events) are
-- intentionally out of scope until the new provider API is defined.

-- 1. Harden the catalog: make city name a reliable alternate key per account.
--    No duplicates exist today (verified), so this is safe.
CREATE UNIQUE INDEX IF NOT EXISTS cities_account_lower_name_key
  ON public.cities (account_id, lower(trim(name)));

-- 2. Backfill panelists.city_id from address_city, matched case-insensitively
--    and scoped to the same account. Only fills rows that don't already have a
--    city_id and whose address_city maps unambiguously to one catalog city.
--    Sub-localities with no matching city (e.g. Nairobi-GPO, JKIA, Kwale/Diani,
--    Buruburu) and cross-account names (Barcelona in an account without it) are
--    intentionally left NULL for manual review.
UPDATE public.panelists p
SET city_id = c.id
FROM public.cities c
WHERE p.city_id IS NULL
  AND p.address_city IS NOT NULL
  AND c.account_id = p.account_id
  AND lower(trim(c.name)) = lower(trim(p.address_city))
  AND (
    SELECT count(*) FROM public.cities c2
    WHERE c2.account_id = p.account_id
      AND lower(trim(c2.name)) = lower(trim(p.address_city))
  ) = 1;
