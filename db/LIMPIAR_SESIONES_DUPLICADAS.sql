-- Limpiar sesiones duplicadas y obsoletas
-- Ejecutar este script una sola vez en el SQL Editor de Supabase

-- 1. Ver sesiones duplicadas por usuario y dispositivo
SELECT 
    user_id,
    device_info,
    COUNT(*) as sesiones_duplicadas,
    MAX(last_activity) as ultima_actividad
FROM user_sessions
GROUP BY user_id, device_info
HAVING COUNT(*) > 1;

-- 2. Eliminar sesiones duplicadas, manteniendo solo la más reciente por usuario/dispositivo
DELETE FROM user_sessions a
USING user_sessions b
WHERE a.user_id = b.user_id
  AND a.device_info = b.device_info
  AND a.last_activity < b.last_activity;

-- 3. Eliminar sesiones inactivas (más de 7 días sin actividad)
DELETE FROM user_sessions
WHERE last_activity < NOW() - INTERVAL '7 days';

-- 4. Verificar resultado - debería mostrar máximo una sesión por usuario/dispositivo
SELECT 
    user_id,
    device_info,
    COUNT(*) as sesiones_activas,
    last_activity
FROM user_sessions
GROUP BY user_id, device_info, last_activity
ORDER BY user_id, device_info;

-- 5. Contar total de sesiones por usuario
SELECT 
    u.email,
    p.role,
    COUNT(s.id) as sesiones_totales
FROM user_sessions s
JOIN auth.users u ON s.user_id = u.id
LEFT JOIN profiles p ON s.user_id = p.id
GROUP BY u.email, p.role
ORDER BY sesiones_totales DESC;
