# Migraciones históricas (pre-baseline) — ARCHIVO

Estas 130 migraciones son el historial que construyó la BD de ONEMS hasta el
**2026-07-14**. Se archivaron aquí (fuera de `supabase/migrations/`, por lo que la
CLI de Supabase **ya no las aplica**) al hacer el *squash* a un baseline.

## Por qué se archivaron

Se auditó el repo contra la BD viva y se comprobó que **no eran reproducibles en
orden**: usaban funciones antes de definirlas, referenciaban columnas inexistentes
(`profiles.user_id`), incluían migraciones muertas (objetos que prod ya dropeó) y
~46 objetos vivos no tenían migración. Un `db reset` desde cero fallaba.

## Qué las reemplaza

`supabase/migrations/00000000000000_baseline_prod_schema.sql` — captura EXACTA del
esquema `public` de prod (introspección pg_catalog), validada objeto por objeto
contra prod en un Postgres 17.6 local (paridad total salvo normalización cosmética
de CHECKs). Desde aquí el desarrollo es **forward-only**: cada cambio nuevo es una
migración con timestamp posterior.

## No borrar

Se conservan como referencia histórica y por si hace falta rastrear el origen de
algún objeto. No las edites ni las devuelvas a `migrations/`.
