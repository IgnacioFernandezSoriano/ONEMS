-- Firma del esquema public: tablas, vistas, funciones (con args), policies, triggers.
-- Debe producir EXACTAMENTE las mismas líneas que _prod_schema_snapshot.txt
-- cuando se ejecuta contra la BD LOCAL tras `supabase db reset`.
-- Uso (psql -t -A) para salida limpia, una firma por línea.
select 'table  '||table_name from information_schema.tables where table_schema='public' and table_type='BASE TABLE'
union all
select 'view   '||table_name from information_schema.views where table_schema='public'
union all
select 'func   '||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prokind='f'
union all
select 'policy '||tablename||' :: '||policyname from pg_policies where schemaname='public'
union all
select 'trigger '||c.relname||' :: '||t.tgname from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal
order by 1;
