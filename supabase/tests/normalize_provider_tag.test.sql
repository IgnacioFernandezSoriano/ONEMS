-- Regla 2026-10-30: la cadena del proveedor es prefijo fijo G.1UPU.01000FFFF + numero impreso.
-- La clave ONEMS es el numero impreso normalizado (normalize_tag), igual que lo teclea el panelista.
DO $$
BEGIN
  -- cadena UPU completa -> numero impreso de 8 digitos
  IF normalize_provider_tag('G.1UPU.01000FFFF00000007') IS DISTINCT FROM '00000007' THEN
    RAISE EXCEPTION 'FAIL: UPU -> numero impreso, got %', normalize_provider_tag('G.1UPU.01000FFFF00000007');
  END IF;
  -- minusculas y espacios
  IF normalize_provider_tag('  g.1upu.01000ffff00000008  ') IS DISTINCT FROM '00000008' THEN
    RAISE EXCEPTION 'FAIL: trim/upper, got %', normalize_provider_tag('  g.1upu.01000ffff00000008  ');
  END IF;
  -- mas de 8 digitos: se respeta tal cual (sin ceros a la izquierda)
  IF normalize_provider_tag('G.1UPU.01000FFFF123456789') IS DISTINCT FROM '123456789' THEN
    RAISE EXCEPTION 'FAIL: 9 digitos, got %', normalize_provider_tag('G.1UPU.01000FFFF123456789');
  END IF;
  -- otro emisor / otro formato -> NULL (tag_decode_failed)
  IF normalize_provider_tag('urn:oid:1.0.15961.14.B.A00122245737') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: urn:oid debe ser NULL';
  END IF;
  IF normalize_provider_tag('30b1d226a8240000b000650c') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: hex suelto debe ser NULL';
  END IF;
  IF normalize_provider_tag('G.1UPU.01000FFFF') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: prefijo sin numero debe ser NULL';
  END IF;
  IF normalize_provider_tag('hello world') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: basura debe ser NULL';
  END IF;
  IF normalize_provider_tag('') IS NOT NULL OR normalize_provider_tag(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: vacio/NULL deben ser NULL';
  END IF;
  RAISE NOTICE 'PASS: normalize_provider_tag';
END $$;
