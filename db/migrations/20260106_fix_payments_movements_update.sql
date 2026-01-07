-- =====================================================
-- FIX: Agregar política UPDATE faltante para payments_movements
-- Fecha: 2026-01-06
-- =====================================================

BEGIN;

-- Agregar política de UPDATE que faltaba
DROP POLICY IF EXISTS movements_update_owner ON public.payments_movements;
CREATE POLICY movements_update_owner
  ON public.payments_movements 
  FOR UPDATE 
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

COMMIT;

-- Verificar que la política se creó correctamente
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE tablename = 'payments_movements'
ORDER BY cmd, policyname;

-- Expected output: Deberías ver 4 políticas:
-- 1. movements_select_owner (SELECT)
-- 2. movements_insert_owner (INSERT)
-- 3. movements_update_owner (UPDATE) <- Esta es la nueva
-- 4. movements_delete_owner (DELETE)
