-- =====================================================
-- SOLUCIÓN COMPLETA: PERFILES FALTANTES
-- =====================================================
-- Ejecuta este script COMPLETO en Supabase SQL Editor

-- 1. VERIFICAR USUARIOS EXISTENTES SIN PERFIL
SELECT 
    'Usuarios en auth.users' as tabla,
    COUNT(*) as cantidad
FROM auth.users
UNION ALL
SELECT 
    'Usuarios en profiles' as tabla,
    COUNT(*) as cantidad
FROM profiles;

-- 2. DESHABILITAR RLS TEMPORALMENTE PARA INSERTAR
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- 3. INSERTAR PERFILES FALTANTES (usando estructura correcta)
INSERT INTO profiles (id, email, full_name, role)
SELECT 
    au.id,
    au.email,
    COALESCE(au.raw_user_meta_data->>'full_name', 'Usuario'),
    'free'
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- 4. VOLVER A HABILITAR RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 5. VERIFICAR PERFILES CREADOS
SELECT 
    id,
    email,
    full_name,
    role,
    updated_at
FROM profiles 
ORDER BY updated_at DESC;

-- 6. CAMBIAR ROL A ADMIN (reemplaza el email con el tuyo)
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'sepagos.email@gmail.com';

-- 7. VERIFICAR CAMBIO DE ROL
SELECT 
    email,
    full_name,
    role,
    CASE 
        WHEN role = 'admin' THEN '✅ Admin'
        WHEN role = 'premium' THEN '⭐ Premium'
        ELSE '👤 Free'
    END as estado
FROM profiles;
