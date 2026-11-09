-- Contactos por rol en la cuenta, para los mensajes automáticos de los agentes.
--
-- Hasta ahora la cuenta tenía un solo contacto, email_panelist_manager, que en la práctica es el
-- Account Manager (el líder del proyecto). A partir de aquí hay cinco roles:
--   email_account_manager      Account Manager (líder del proyecto)          NUEVA (se copia el valor actual)
--   email_panelist_manager     Panelist Manager                              SE MANTIENE (mismo nombre)
--   email_materials_supplier   Materials Supplier                            NUEVA
--   email_do_coordinator       DO coordinator (operador designado)           NUEVA
--   email_upu_account_manager  UPU account manager                           NUEVA
--
-- Por qué no se renombra email_panelist_manager: lo leen 7 flujos de n8n del bot de panelistas
-- (avisos de incidencias, material, cartas no recibidas…) y la función due_unread_reply_notifications.
-- Renombrarla los rompería en producción. Se mantiene con su nombre, ahora con el significado de
-- Panelist Manager, y conserva su valor, así que esos avisos siguen llegando a la misma persona hasta
-- que el manager ponga el Panelist Manager real.
--
-- Solo añade columnas y copia un valor: no borra ni cambia nada. Las políticas RLS de accounts
-- (superadmin gestiona; cada usuario ve solo su cuenta) cubren también las columnas nuevas.

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS email_account_manager     text NULL,
  ADD COLUMN IF NOT EXISTS email_materials_supplier  text NULL,
  ADD COLUMN IF NOT EXISTS email_do_coordinator      text NULL,
  ADD COLUMN IF NOT EXISTS email_upu_account_manager text NULL;

-- El contacto actual es el Account Manager: se copia (solo donde aún no hay valor).
UPDATE public.accounts
   SET email_account_manager = email_panelist_manager
 WHERE email_account_manager IS NULL
   AND email_panelist_manager IS NOT NULL;

-- Formato mínimo de email (vacío = sin contacto). NOT VALID + VALIDATE para no bloquear la tabla.
DO $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY ARRAY['email_account_manager','email_panelist_manager','email_materials_supplier',
                           'email_do_coordinator','email_upu_account_manager'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                    WHERE conrelid = 'public.accounts'::regclass AND conname = 'accounts_' || c || '_format') THEN
      EXECUTE format('ALTER TABLE public.accounts ADD CONSTRAINT %I CHECK (%I IS NULL OR %I ~* %L) NOT VALID',
                     'accounts_' || c || '_format', c, c, '^[^@\s]+@[^@\s]+\.[^@\s]+$');
      EXECUTE format('ALTER TABLE public.accounts VALIDATE CONSTRAINT %I', 'accounts_' || c || '_format');
    END IF;
  END LOOP;
END $$;

COMMENT ON COLUMN public.accounts.email_account_manager     IS 'Account Manager: líder del proyecto en la cuenta. Destinatario de los informes de operación del agente.';
COMMENT ON COLUMN public.accounts.email_panelist_manager    IS 'Panelist Manager: gestiona a los panelistas (incidencias, bajas, avisos del bot). Nombre de columna histórico.';
COMMENT ON COLUMN public.accounts.email_materials_supplier  IS 'Materials Supplier: proveedor de materiales (sobres, sellos, transpondedores).';
COMMENT ON COLUMN public.accounts.email_do_coordinator      IS 'DO coordinator: coordinador del operador designado (correos del país).';
COMMENT ON COLUMN public.accounts.email_upu_account_manager IS 'UPU account manager: responsable de la cuenta en la UPU.';
