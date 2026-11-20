SELECT id, name, slug, timezone, (SELECT count(*) FROM public.cities c WHERE c.account_id = a.id) AS cities,
       (SELECT count(*) FROM public.carriers c WHERE c.account_id = a.id) AS carriers,
       (SELECT count(*) FROM public.products c WHERE c.account_id = a.id) AS products,
       (SELECT count(*) FROM public.postal_centers c WHERE c.account_id = a.id) AS postal_centers,
       (SELECT count(*) FROM public.readers c WHERE c.account_id = a.id) AS readers,
       (SELECT count(*) FROM public.delivery_standards c WHERE c.account_id = a.id) AS standards,
       (SELECT count(*) FROM public.one_db c WHERE c.account_id = a.id) AS one_db
  FROM public.accounts a WHERE a.slug = 'DEMO2';
