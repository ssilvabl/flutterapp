-- =====================================================
-- TABLA DE SESIONES Y LÍMITES DE USUARIOS
-- =====================================================

-- 1. Crear tabla para rastrear sesiones activas
CREATE TABLE IF NOT EXISTS public.user_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_token TEXT NOT NULL,
  device_info TEXT,
  last_activity TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(session_token)
);

-- 2. Crear índice para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_user_sessions_user_id ON public.user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sessions_last_activity ON public.user_sessions(last_activity);

-- 3. Habilitar RLS
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;

-- 4. Políticas RLS para user_sessions
DROP POLICY IF EXISTS "Users can view own sessions" ON user_sessions;
CREATE POLICY "Users can view own sessions"
ON user_sessions FOR SELECT
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own sessions" ON user_sessions;
CREATE POLICY "Users can insert own sessions"
ON user_sessions FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own sessions" ON user_sessions;
CREATE POLICY "Users can update own sessions"
ON user_sessions FOR UPDATE
USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own sessions" ON user_sessions;
CREATE POLICY "Users can delete own sessions"
ON user_sessions FOR DELETE
USING (auth.uid() = user_id);

-- 5. Función para limpiar sesiones inactivas (más de 30 días)
CREATE OR REPLACE FUNCTION public.cleanup_inactive_sessions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.user_sessions
  WHERE last_activity < NOW() - INTERVAL '30 days';
END;
$$;

-- 6. Función para obtener el conteo de sesiones activas de un usuario
CREATE OR REPLACE FUNCTION public.get_active_sessions_count(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  session_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO session_count
  FROM public.user_sessions
  WHERE user_id = p_user_id
  AND last_activity > NOW() - INTERVAL '7 days'; -- Sesiones activas en los últimos 7 días
  
  RETURN session_count;
END;
$$;

-- 7. Función para eliminar las sesiones más antiguas de un usuario
CREATE OR REPLACE FUNCTION public.remove_oldest_sessions(p_user_id UUID, p_keep_count INTEGER)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.user_sessions
  WHERE id IN (
    SELECT id FROM public.user_sessions
    WHERE user_id = p_user_id
    ORDER BY last_activity ASC
    LIMIT (
      SELECT GREATEST(0, COUNT(*) - p_keep_count)
      FROM public.user_sessions
      WHERE user_id = p_user_id
    )
  );
END;
$$;

-- 8. Ver sesiones activas (para pruebas)
-- SELECT * FROM user_sessions ORDER BY last_activity DESC;
