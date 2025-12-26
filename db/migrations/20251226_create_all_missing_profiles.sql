-- =====================================================
-- VERIFICAR Y CREAR TODOS LOS PERFILES FALTANTES
-- =====================================================

-- 1. VER USUARIOS EN auth.users
SELECT 
    id,
    email,
    created_at,
    'En auth.users' as ubicacion
FROM auth.users
ORDER BY created_at DESC;

-- 2. VER USUARIOS EN profiles
SELECT 
    id,
    email,
    full_name,
    role,
    'En profiles' as ubicacion
FROM profiles
ORDER BY updated_at DESC;

-- 3. VER USUARIOS QUE ESTÁN EN auth.users PERO NO EN profiles
SELECT 
    au.id,
    au.email,
    au.created_at,
    '❌ SIN PERFIL' as estado
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL;

-- 4. CREAR PERFILES PARA USUARIOS SIN PERFIL
-- Deshabilitar RLS temporalmente
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- Insertar perfiles faltantes
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

-- Habilitar RLS nuevamente
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 5. VERIFICAR QUE AHORA TODOS TENGAN PERFIL
SELECT 
    au.id,
    au.email,
    CASE 
        WHEN p.id IS NOT NULL THEN '✅ Con perfil'
        ELSE '❌ Sin perfil'
    END as estado,
    p.role
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
ORDER BY au.created_at DESC;

-- 6. VER TODOS LOS PERFILES CREADOS
SELECT 
    id,
    email,
    full_name,
    role,
    company,
    updated_at
FROM profiles
ORDER BY updated_at DESC;
