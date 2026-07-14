-- Firma del esquema public: una linea por objeto (ordenable/diffeable).
-- Se corre igual en prod (API) y en local para comparar paridad.
select line from (
  -- columnas: tabla.columna tipo [notnull]
  select 't:'||c.relname||'.'||a.attname||' '||format_type(a.atttypid,a.atttypmod)||
         case when a.attnotnull then ' NN' else '' end as line
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
  where n.nspname='public' and c.relkind='r'
  union all
  -- constraints
  select 'c:'||c.relname||'.'||con.conname||' '||pg_get_constraintdef(con.oid)
  from pg_constraint con join pg_class c on c.oid=con.conrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
  union all
  -- indexes
  select 'i:'||i.relname||' '||pg_get_indexdef(ix.indexrelid)
  from pg_index ix join pg_class i on i.oid=ix.indexrelid
  join pg_class c on c.oid=ix.indrelid join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'
  union all
  -- funciones: nombre(args) -> rettype
  select 'f:'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  union all
  -- vistas
  select 'v:'||c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='v'
  union all
  -- policies: tabla.policy cmd roles
  select 'p:'||tablename||'.'||policyname||' '||cmd||' {'||array_to_string(roles,',')||'}'
  from pg_policies where schemaname='public'
  union all
  -- triggers
  select 'g:'||c.relname||'.'||t.tgname
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and not t.tgisinternal
) s order by line;
