-- Migration: 2025-12-24
-- Añade campos para soportar entity_name, tipo, fecha fin y descripción.
-- Migra datos desde client_name a entity_name y normaliza amount a numeric(12,2).
-- Habilita RLS y crea las políticas necesarias.
-- ENFOQUE: idempotente; puedes ejecutar varias veces sin romper el esquema.

BEGIN;

-- 1) Crear columnas nuevas (idempotente)
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS entity_name text,
  ADD COLUMN IF NOT EXISTS type text NOT NULL DEFAULT 'cobro',
  ADD COLUMN IF NOT EXISTS end_date timestamptz,
  ADD COLUMN IF NOT EXISTS description text;

-- 2) Migrar datos: copiar client_name -> entity_name si aún no existe
UPDATE public.payments
SET entity_name = client_name
WHERE entity_name IS NULL AND client_name IS NOT NULL;

-- 3) Normalizar amount a numeric(12,2)
-- Este bloque intenta convertir amount a numeric con 2 decimales.
-- Comprueba si la conversión es segura para tu dataset antes de ejecutar.
ALTER TABLE public.payments
  ALTER COLUMN amount TYPE numeric(12,2)
  USING (CASE
    WHEN amount IS NULL THEN 0
    WHEN pg_typeof(amount) = 'text'::regtype THEN (NULLIF(regexp_replace(amount::text, '[^0-9\.]', '', 'g'), '')::numeric)
    ELSE amount::numeric
  END);

-- 4) Índices (mejora rendimiento en consultas por usuario)
CREATE INDEX IF NOT EXISTS idx_payments_userid ON public.payments (user_id);

-- 5) Habilitar RLS y políticas (DROP+CREATE por compatibilidad con Postgres)
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payments_select_owner ON public.payments;
CREATE POLICY payments_select_owner
  ON public.payments FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS payments_insert_owner ON public.payments;
CREATE POLICY payments_insert_owner
  ON public.payments FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS payments_update_owner ON public.payments;
CREATE POLICY payments_update_owner
  ON public.payments FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS payments_delete_owner ON public.payments;
CREATE POLICY payments_delete_owner
  ON public.payments FOR DELETE USING (user_id = auth.uid());

COMMIT;

-- 6) Opcional: eliminar la columna client_name (descomenta y ejecuta solo cuando hayas verificado durante 24-48h)
-- ALTER TABLE public.payments DROP COLUMN IF EXISTS client_name;

-- Verificaciones útiles (ejecuta manualmente después de migrar):
-- SELECT id, entity_name, client_name, amount::text, end_date, type, description FROM public.payments ORDER BY created_at DESC LIMIT 20;
-- SELECT * FROM pg_policies WHERE schemaname='public' AND tablename='payments';

-- Rollback (si todo falla): restaura desde backup (pg_dump) o usa las instrucciones de reversión manuales.
