-- =====================================================
-- CORREGIR PERMISOS DE ADMINISTRADOR PARA CAMBIAR ROLES
-- =====================================================
-- Fecha: 27 de diciembre de 2024
-- Ejecutar en Supabase SQL Editor

-- Problema: Los administradores no pueden cambiar el rol de otros usuarios
-- porque la política RLS solo permite actualizar el propio perfil

-- 1. Crear política para que administradores puedan actualizar cualquier perfil
DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;

CREATE POLICY "Admins can update all profiles"
ON profiles FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() 
    AND role = 'admin'
  )
);

-- 2. Verificar las políticas actuales
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY policyname;

-- =====================================================
-- NOTA: Esta política permite que los usuarios con rol 'admin'
-- puedan actualizar cualquier perfil en la tabla profiles
-- =====================================================
