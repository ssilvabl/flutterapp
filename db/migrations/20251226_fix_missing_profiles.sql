-- =====================================================
-- SCRIPT DE EMERGENCIA: CREAR PERFILES FALTANTES
-- =====================================================
-- Este script crea perfiles para usuarios que ya existen en auth.users
-- pero no tienen registro en la tabla profiles

-- PASO 1: Ver los usuarios que existen en auth pero no tienen perfil
SELECT 
    au.id,
    au.email,
    au.created_at,
    CASE WHEN p.id IS NULL THEN '❌ Sin perfil' ELSE '✅ Con perfil' END as estado
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
ORDER BY au.created_at DESC;

-- PASO 2: Insertar perfiles para usuarios sin perfil
-- (Ejecuta esto DESPUÉS de ver los resultados del PASO 1)
INSERT INTO profiles (id, email, full_name, role)
SELECT 
    au.id,
    au.email,
    COALESCE(au.raw_user_meta_data->>'full_name', 'Usuario'),
    'free'
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL;

-- PASO 3: Verificar que se crearon los perfiles
SELECT * FROM profiles ORDER BY updated_at DESC;

-- PASO 4: Ahora SÍ puedes cambiar el rol del usuario a admin
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'sepagos.email@gmail.com';

-- PASO 5: Verificar el cambio
SELECT id, email, full_name, role FROM profiles;
