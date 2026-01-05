-- =====================================================
-- VERIFICAR Y CORREGIR SUSCRIPCIÓN DE USUARIO
-- =====================================================

-- 1. Ver el estado actual del usuario
SELECT 
    id,
    email,
    role,
    subscription_start,
    subscription_end,
    subscription_cancelled,
    updated_at
FROM profiles
WHERE email = 'santiagosilvabl@gmail.com';

-- 2. Si tiene subscription_end pero role='free', hay un problema de sincronización
-- Ejecuta esto para limpiar y resetear:

UPDATE profiles
SET 
    role = 'free',
    subscription_start = NULL,
    subscription_end = NULL,
    subscription_cancelled = NULL,
    updated_at = NOW()
WHERE email = 'santiagosilvabl@gmail.com';

-- 3. Verificar que se limpió correctamente
SELECT 
    id,
    email,
    role,
    subscription_start,
    subscription_end,
    subscription_cancelled
FROM profiles
WHERE email = 'santiagosilvabl@gmail.com';

-- 4. Ahora prueba hacer un pago de nuevo desde la app
