-- Datos de prueba para la pantalla "Incidencias reportadas" v2 — cuenta DEMO2 (f4d823d2-93e6-4755-9a89-9da87e7fa86e)
-- Proyecto: onems-dev (sehbnpgzqljrsqimwyuz). TODO lo creado lleva la marca [TEST-V2] en la descripcion
-- o esta listado en el bloque de limpieza de abajo. No toca los datos de prueba anteriores (TEST-INCIDENCIAS...).

-- ===== CREAR =====
DO $$
DECLARE
  acc   constant uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  ny03  uuid; ny02 uuid; bal01 uuid; la02 uuid; sac01 uuid;
  env_id uuid; seal_id uuid;
  det_ret uuid := '6bd228e5-ede3-4868-b45c-622076888fb4';  -- muestra 'sent' BAL-01 -> SAC-01 (2026-11-18)
BEGIN
  SELECT id INTO ny03  FROM panelists WHERE account_id = acc AND panelist_code = 'PAN-NY-03';
  SELECT id INTO ny02  FROM panelists WHERE account_id = acc AND panelist_code = 'PAN-NY-02';
  SELECT id INTO bal01 FROM panelists WHERE account_id = acc AND panelist_code = 'PAN-BAL-01';
  SELECT id INTO la02  FROM panelists WHERE account_id = acc AND panelist_code = 'PAN-LA-02';
  SELECT id INTO env_id  FROM material_catalog WHERE account_id = acc AND code = 'EX-ENV-01';
  SELECT id INTO seal_id FROM material_catalog WHERE account_id = acc AND code = 'SEAL-01';

  -- Material bloqueante: el sobre (para ver "dias sin stock" y muestras afectadas)
  UPDATE material_catalog SET is_blocking = true WHERE id = env_id;

  -- Stock central parcial (cubre solo 300 de los sobres que necesita NY-03 -> reparto central + donante)
  INSERT INTO material_stocks (account_id, material_id, quantity, location_type)
  VALUES (acc, env_id, 300, 'central');

  -- Stock que "nos consta" del panelista que reporta (NY-03) y excedente del donante (NY-02, misma ciudad)
  INSERT INTO panelist_material_stocks (account_id, panelist_id, material_id, quantity) VALUES
    (acc, ny03, env_id, 100), (acc, ny03, seal_id, 200),
    (acc, ny02, env_id, 5000), (acc, ny02, seal_id, 6000);

  -- A: falta de material (NY-03)
  PERFORM insert_panelist_incident_auto(ny03, 'missing_materials',
    '[TEST-V2] Me faltan sobres y precintos para los proximos envios',
    '{"materials":[{"name":"Express Document Envelope","quantity":0},{"name":"Tamper-Evident Seal","quantity":0}]}'::jsonb,
    NULL, 'open');
  -- D: devuelto (BAL-01 es el emisor de la muestra)
  PERFORM insert_panelist_incident_auto(bal01, 'parcel_returned',
    '[TEST-V2] El paquete me ha sido devuelto por el transportista', NULL, det_ret, 'open');
  -- E: como enviar (al manager de momento)
  PERFORM insert_panelist_incident_auto(la02, 'how_to_send',
    '[TEST-V2] No se como preparar el envio de tipo express', NULL, NULL, 'open');
  -- C: roto (registro automatico)
  PERFORM insert_panelist_incident_auto(bal01, 'parcel_damaged',
    '[TEST-V2] El paquete llego golpeado', NULL, det_ret, 'auto_resolved');
  -- B: etiqueta ilegible (automatica)
  PERFORM insert_panelist_incident_auto(ny02, 'unreadable_label_receipt',
    '[TEST-V2] No puedo leer la etiqueta del paquete recibido',
    jsonb_build_object('chosen_detail_id', det_ret), det_ret, 'auto_resolved');
  -- H: cambio de contacto (automatica)
  PERFORM insert_panelist_incident_auto(la02, 'contact_data_change',
    '[TEST-V2] Cambio de telefono',
    '{"before":{"mobile":"+1-555-0100"},"after":{"mobile":"+1-555-0199"},"applied":true}'::jsonb, NULL, 'auto_resolved');
END $$;

-- ===== LIMPIAR (cuando acabes de probar) =====
-- Ojo: si probaste el flujo A hasta el final, tambien habra envios de material y una baja 'materials' de PAN-NY-03
-- (se ven en Stock > Envios y en Disponibilidad de panelistas); borrarlos desde la app o preguntar.
-- DELETE FROM panelist_incident WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND description LIKE '[TEST-V2]%';
-- DELETE FROM panelist_material_stocks WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
--   AND panelist_id IN (SELECT id FROM panelists WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND panelist_code IN ('PAN-NY-02','PAN-NY-03'));
-- DELETE FROM material_stocks WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND location_type = 'central'
--   AND material_id = (SELECT id FROM material_catalog WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND code = 'EX-ENV-01');
-- UPDATE material_catalog SET is_blocking = false WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND code = 'EX-ENV-01';
