// deno-lint-ignore-file require-await no-import-prefix
// Prueba de contrato worker <-> base REAL (Postgres local, nunca la remota). Opcional: solo con CL_IT=1 y despues de
// `bash .superpowers/sdd/runlocal.sh` (que deja la base onems_t con todas las migraciones). Copia onems_t en
// onems_it, crea una entrega con un fichero JSON Lines generado, ejecuta el worker con las RPC reales (llamadas con
// argumentos con nombre, como PostgREST) y el procedimiento de pg_cron (CALL con COMMIT entre pasos), y comprueba el
// resultado. Borra onems_it al terminar.
//   CL_IT=1 PGPASSWORD=postgres deno test -A integration_test.ts
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { DEFAULTS, runOnce, type WorkerIo } from './loader.ts'

// Sin permiso de entorno (deno test sin -A) la prueba se ignora.
const env = (k: string): string | undefined => { try { return Deno.env.get(k) } catch { return undefined } }
const PSQL = env('CL_IT_PSQL') ?? 'C:/Users/fernandezi/pgportable/pgsql/bin/psql.exe'
const CONN = ['-h', '127.0.0.1', '-p', '5433', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-X', '-q', '-At']

async function psql(db: string, sql: string): Promise<string> {
  const p = new Deno.Command(PSQL, { args: [...CONN, '-d', db], stdin: 'piped', stdout: 'piped', stderr: 'piped',
                                     env: { PGPASSWORD: env('PGPASSWORD') ?? 'postgres' } }).spawn()
  const w = p.stdin.getWriter()
  await w.write(new TextEncoder().encode(sql))
  await w.close()
  const o = await p.output()
  const err = new TextDecoder().decode(o.stderr)
  if (!o.success) throw { message: err.replace(/^.*ERROR:\s+/s, '').split('\n')[0] }
  return new TextDecoder().decode(o.stdout).trim()
}

const q = (s: string) => `'${s.replaceAll("'", "''")}'`

// Llamada con argumentos con nombre y el tipo declarado de cada uno (como hace PostgREST con un cuerpo JSON).
const CALL_HELPER = `
CREATE OR REPLACE FUNCTION public.zz_it_call(p_fn text, p_args jsonb) RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE v_sql text; v_res jsonb; a record; v_list text[] := ARRAY[]::text[];
BEGIN
  FOR a IN SELECT n.name, format_type(t.oid, NULL) AS typ
             FROM pg_proc p, unnest(p.proargnames, p.proargtypes::oid[]) WITH ORDINALITY n(name, typ, o)
             JOIN pg_type t ON t.oid = n.typ
            WHERE p.oid = (SELECT oid FROM pg_proc WHERE proname = p_fn AND pronamespace = 'public'::regnamespace)
              AND p_args ? n.name LOOP
    v_list := v_list || CASE
      WHEN a.typ = 'jsonb' THEN format('%I => %L::jsonb', a.name, p_args->a.name)
      WHEN a.typ = 'text[]' THEN format('%I => ARRAY(SELECT jsonb_array_elements_text(%L::jsonb))', a.name, p_args->a.name)
      ELSE format('%I => %L::%s', a.name, p_args->>a.name, a.typ) END;
  END LOOP;
  EXECUTE format('SELECT to_jsonb(public.%I(%s))', p_fn, array_to_string(v_list, ', ')) INTO v_res;
  RETURN v_res;
END $f$;`

const FIXTURE = `
INSERT INTO public.accounts (id, name, slug, timezone) VALUES ('a0000000-0000-0000-0000-0000000000e1','IT','it','Africa/Nairobi');
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','R','R');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e1','C1','C1'),
  ('c2000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-0000000000e1','e0000000-0000-0000-0000-0000000000e1','C2','C2');
INSERT INTO public.carriers (id, account_id, code, name) VALUES ('ca000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','ca000000-0000-0000-0000-0000000000e1','PR','Prod',48);
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','P1','P1','C1','c1000000-0000-0000-0000-0000000000e1'),
  ('d2000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-0000000000e1','P2','P2','C2','c2000000-0000-0000-0000-0000000000e2');
INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('a0000000-0000-0000-0000-0000000000e1','d1000000-0000-0000-0000-0000000000e1','O','Entry','carrier_scan','ca000000-0000-0000-0000-0000000000e1','NBO',NULL,'origin'),
  ('a0000000-0000-0000-0000-0000000000e1','d2000000-0000-0000-0000-0000000000e2','D','Exit','carrier_scan','ca000000-0000-0000-0000-0000000000e1','MBA',NULL,'destination');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','ca000000-0000-0000-0000-0000000000e1','F','active','{2}',3);
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-0000000000e1','ca000000-0000-0000-0000-0000000000e1','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-0000000000e1','ca000000-0000-0000-0000-0000000000e1','scan_at','ts',NULL,NULL),
  ('a0000000-0000-0000-0000-0000000000e1','ca000000-0000-0000-0000-0000000000e1','place_ref','office',NULL,NULL);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1','P','ca000000-0000-0000-0000-0000000000e1','cb000000-0000-0000-0000-0000000000e1',10,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000e1');
INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('a0000000-0000-0000-0000-0000000000e1','90000000-0000-0000-0000-0000000000e1','c1000000-0000-0000-0000-0000000000e1','c2000000-0000-0000-0000-0000000000e2',2026,46,'2026-11-09','2026-11-15',7);
`

Deno.test({
  name: 'integration: worker + real RPCs + CALL cl_delivery_process_run',
  ignore: env('CL_IT') !== '1',
  sanitizeResources: false,
  sanitizeOps: false,
  async fn() {
    await psql('postgres', 'DROP DATABASE IF EXISTS onems_it WITH (FORCE); CREATE DATABASE onems_it TEMPLATE onems_t;')
    try {
      await psql('onems_it', CALL_HELPER + FIXTURE)
      // 400 envios con 3 lecturas (origen, intermedia desconocida, destino); CRLF; campo personal que no debe llegar.
      let text = ''
      for (let i = 1; i <= 400; i++) {
        text += JSON.stringify({ trk: 'K' + i, ts: '2026-11-10 08:00+03', office: 'NBO', name: 'Persona ' + i }) + '\r\n'
        text += JSON.stringify({ trk: 'K' + i, ts: '2026-11-11 08:00+03', office: 'HUBX' }) + '\r\n'
        text += JSON.stringify({ trk: 'K' + i, ts: '2026-11-12 08:00+03', office: 'MBA' }) + '\r\n'
      }
      const file = new TextEncoder().encode(text)
      const sha = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', file)),
                             (x) => x.toString(16).padStart(2, '0')).join('')
      await psql('onems_it', `INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source,
        format, compression, file_path, file_bytes, sha256, status, received_at)
        VALUES ('de000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-0000000000e1',
                'f0000000-0000-0000-0000-0000000000e1','2026-11-10','2026-11-16','api','jsonl','none','x/y/z.jsonl',
                ${file.length}, ${q(sha)}, 'received', now());`)

      const io: WorkerIo = {
        async rpc(fn, args) {
          const out = await psql('onems_it', `SELECT public.zz_it_call(${q(fn)}, ${q(JSON.stringify(args))}::jsonb);`)
          return out === '' ? null : JSON.parse(out)
        },
        async fetchRange(_p, s, e) { return file.slice(s, e) },
        async remove(_p) {},
        now: () => Date.now(),
      }
      const opt = { ...DEFAULTS, token: 'token-it-0001', chunkBytes: 20_000, rowsPerRpc: 150, maxChunks: 3 }
      let res
      for (let i = 0; i < 50; i++) {
        res = await runOnce(io, opt)
        if (res.status !== 'more') break
      }
      assertEquals(res?.status, 'loaded')
      assertEquals(await psql('onems_it', `SELECT rows_total FROM public.cl_deliveries WHERE id = 'de000000-0000-0000-0000-0000000000e1'`), '1200')
      assertEquals(await psql('onems_it', `SELECT count(*) FROM public.cl_delivery_rows WHERE extra IS NOT NULL OR item_id LIKE 'Persona%'`), '0')

      // Procedimiento de pg_cron (fuera de transaccion: COMMIT entre pasos).
      await psql('onems_it', 'CALL public.cl_delivery_process_run(50000, 250);')
      const d = await psql('onems_it', `SELECT status || '|' || shipments_total || '|' || shipments_valid || '|' ||
          shipments_drawn || '|' || rows_rejected || '|' || (progress->>'phase') FROM public.cl_deliveries
          WHERE id = 'de000000-0000-0000-0000-0000000000e1'`)
      assertEquals(d, 'processed|400|400|7|400|done')
      assertEquals(await psql('onems_it', `SELECT (SELECT count(*) FROM public.cl_delivery_rows) + (SELECT count(*) FROM public.cl_delivery_items)`), '0')
      assertEquals(await psql('onems_it', `SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id
          WHERE s.delivery_id = 'de000000-0000-0000-0000-0000000000e1'`), '7')
      assertEquals(await psql('onems_it', `SELECT status FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000e1'`), 'fulfilled')
      // Idle: otra ejecucion no hace nada; el worker queda idle.
      await psql('onems_it', 'CALL public.cl_delivery_process_run();')
      assertEquals((await runOnce(io, opt)).status, 'idle')
    } finally {
      await psql('postgres', 'DROP DATABASE IF EXISTS onems_it WITH (FORCE);')
    }
  },
})
