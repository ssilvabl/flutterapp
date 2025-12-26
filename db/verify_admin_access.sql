-- =====================================================
-- VERIFICAR Y CORREGIR POLÍTICAS RLS PARA ADMIN
-- =====================================================

-- 1. Ver políticas actuales de profiles
SELECT policyname, cmd, qual 
FROM pg_policies 
WHERE tablename = 'profiles';

-- 2. Ver políticas actuales de payments
SELECT policyname, cmd, qual 
FROM pg_policies 
WHERE tablename = 'payments';

-- 3. Si no ves la política de lectura para todos los usuarios autenticados,
--    ejecuta esto:

-- Eliminar política anterior si existe
DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON profiles;

-- Crear política que permite a usuarios autenticados ver todos los perfiles
CREATE POLICY "Enable read access for all authenticated users"
ON profiles FOR SELECT
USING (auth.role() = 'authenticated');

-- 4. Verificar que la política se creó
SELECT policyname, cmd 
FROM pg_policies 
WHERE tablename = 'profiles' AND cmd = 'SELECT';

-- 5. Probar manualmente (ejecuta esto siendo el usuario admin)
SELECT id, email, full_name, role FROM profiles;

-- Si esto funciona, la app también debería funcionar
