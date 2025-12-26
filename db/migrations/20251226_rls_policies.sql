-- =====================================================
-- POLÍTICAS DE SEGURIDAD PARA PROFILES (SIN RECURSIÓN)
-- =====================================================
-- Ejecutar en Supabase SQL Editor

-- 1. DESHABILITAR RLS TEMPORALMENTE PARA LIMPIAR
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;

-- 3. HABILITAR RLS NUEVAMENTE
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 4. POLÍTICA SIMPLE: Permitir que usuarios creen su propio perfil
CREATE POLICY "Enable insert for users based on user_id"
ON profiles FOR INSERT
WITH CHECK (auth.uid() = id);

-- 5. POLÍTICA SIMPLE: Permitir que usuarios lean su propio perfil
CREATE POLICY "Enable read access for users based on user_id"
ON profiles FOR SELECT
USING (auth.uid() = id);

-- 6. POLÍTICA SIMPLE: Permitir que usuarios actualicen su propio perfil
CREATE POLICY "Enable update for users based on user_id"
ON profiles FOR UPDATE
USING (auth.uid() = id);

-- 7. POLÍTICA: Permitir lectura pública de profiles (para el panel admin)
-- Los admins necesitan leer otros perfiles, pero sin recursión
CREATE POLICY "Enable read access for all authenticated users"
ON profiles FOR SELECT
USING (auth.role() = 'authenticated');

-- =====================================================
-- POLÍTICAS DE SEGURIDAD PARA PAYMENTS
-- =====================================================

-- 1. DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE payments DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR POLÍTICAS EXISTENTES
DROP POLICY IF EXISTS "Users can view own payments" ON payments;
DROP POLICY IF EXISTS "Users can insert own payments" ON payments;
DROP POLICY IF EXISTS "Users can update own payments" ON payments;
DROP POLICY IF EXISTS "Users can delete own payments" ON payments;
DROP POLICY IF EXISTS "Admins can view all payments" ON payments;

-- 3. HABILITAR RLS
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- 4. POLÍTICA: Usuarios pueden ver solo sus pagos
CREATE POLICY "Enable read access for users based on user_id"
ON payments FOR SELECT
USING (auth.uid() = user_id);

-- 5. POLÍTICA: Usuarios pueden insertar sus propios pagos
CREATE POLICY "Enable insert for users based on user_id"
ON payments FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 6. POLÍTICA: Usuarios pueden actualizar sus propios pagos
CREATE POLICY "Enable update for users based on user_id"
ON payments FOR UPDATE
USING (auth.uid() = user_id);

-- 7. POLÍTICA: Usuarios pueden eliminar sus propios pagos
CREATE POLICY "Enable delete for users based on user_id"
ON payments FOR DELETE
USING (auth.uid() = user_id);

-- =====================================================
-- VERIFICACIÓN
-- =====================================================

-- Verificar políticas de profiles
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY policyname;

-- Verificar políticas de payments
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'payments'
ORDER BY policyname;
