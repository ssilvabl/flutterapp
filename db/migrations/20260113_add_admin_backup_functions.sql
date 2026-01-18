-- ============================================
-- FUNCIONES RPC PARA BACKUP COMPLETO DE ADMIN
-- ============================================
-- Estas funciones permiten a los administradores obtener
-- TODOS los datos de TODOS los usuarios para backup completo
-- Ejecutar este script en Supabase SQL Editor

-- Eliminar funciones existentes si existen
DROP FUNCTION IF EXISTS get_all_profiles_admin();
DROP FUNCTION IF EXISTS get_all_payments_admin();
DROP FUNCTION IF EXISTS get_all_movements_admin();
DROP FUNCTION IF EXISTS get_all_sessions_admin();
DROP FUNCTION IF EXISTS get_all_mercadopago_payments_admin();
DROP FUNCTION IF EXISTS get_all_subscriptions_admin();

-- Función para obtener todos los perfiles (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_profiles_admin()
RETURNS TABLE (
  id UUID,
  email TEXT,
  full_name TEXT,
  company TEXT,
  role TEXT,
  subscription_start TIMESTAMP WITH TIME ZONE,
  subscription_end TIMESTAMP WITH TIME ZONE,
  subscription_cancelled BOOLEAN,
  interface_preference TEXT,
  updated_at TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER -- Ejecuta con privilegios del creador (bypasea RLS)
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Verificar que el usuario actual es administrador
  -- Si auth.uid() es NULL (SQL Editor), permitir ejecución
  -- Si auth.uid() existe (app), verificar que sea admin
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  -- Retornar todos los perfiles
  RETURN QUERY
  SELECT 
    p.id,
    p.email,
    p.full_name,
    p.company,
    p.role,
    p.subscription_start,
    p.subscription_end,
    p.subscription_cancelled,
    p.interface_preference,
    p.updated_at
  FROM profiles p
  ORDER BY p.updated_at DESC;
END;
$$;

-- Función para obtener todos los pagos (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_payments_admin()
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  entity_name TEXT,
  amount NUMERIC(15,2),
  type TEXT,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  end_date TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  RETURN QUERY
  SELECT 
    p.id,
    p.user_id,
    p.entity_name,
    p.amount,
    p.type,
    p.description,
    p.created_at,
    p.end_date
  FROM payments p
  ORDER BY p.created_at DESC;
END;
$$;

-- Función para obtener todos los movimientos (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_movements_admin()
RETURNS TABLE (
  id BIGINT,
  payment_id BIGINT,
  user_id UUID,
  amount NUMERIC(15,2),
  movement_type TEXT,
  note TEXT,
  created_at TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  RETURN QUERY
  SELECT 
    pm.id,
    pm.payment_id,
    pm.user_id,
    pm.amount,
    pm.movement_type,
    pm.note,
    pm.created_at
  FROM payments_movements pm
  ORDER BY pm.created_at DESC;
END;
$$;

-- Función para obtener todas las sesiones (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_sessions_admin()
RETURNS TABLE (
  id UUID,
  user_id UUID,
  device_info TEXT,
  created_at TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  RETURN QUERY
  SELECT 
    us.id,
    us.user_id,
    us.device_info,
    us.created_at
  FROM user_sessions us
  ORDER BY us.created_at DESC;
END;
$$;

-- Función para obtener todos los pagos de MercadoPago (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_mercadopago_payments_admin()
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  payment_id TEXT,
  preference_id TEXT,
  status TEXT,
  amount NUMERIC(15,2),
  payment_method TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  RETURN QUERY
  SELECT 
    mp.id,
    mp.user_id,
    mp.payment_id,
    mp.preference_id,
    mp.status,
    mp.amount,
    mp.payment_method,
    mp.created_at,
    mp.updated_at
  FROM mercadopago_payments mp
  ORDER BY mp.created_at DESC;
END;
$$;

-- Función para obtener todas las suscripciones (requiere rol admin)
CREATE OR REPLACE FUNCTION get_all_subscriptions_admin()
RETURNS TABLE (
  id BIGINT,
  user_id UUID,
  plan TEXT,
  status TEXT,
  start_date TIMESTAMP WITH TIME ZONE,
  end_date TIMESTAMP WITH TIME ZONE,
  auto_renew BOOLEAN,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
)
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Solo administradores pueden ejecutar esta función';
  END IF;

  RETURN QUERY
  SELECT 
    s.id,
    s.user_id,
    s.plan,
    s.status,
    s.start_date,
    s.end_date,
    s.auto_renew,
    s.created_at,
    s.updated_at
  FROM subscriptions s
  ORDER BY s.created_at DESC;
END;
$$;

-- ============================================
-- COMENTARIOS Y DOCUMENTACIÓN
-- ============================================
COMMENT ON FUNCTION get_all_profiles_admin() IS 
'Función administrativa para obtener todos los perfiles de usuarios. Solo accesible por administradores.';

COMMENT ON FUNCTION get_all_payments_admin() IS 
'Función administrativa para obtener todos los pagos/cobros. Solo accesible por administradores.';

COMMENT ON FUNCTION get_all_movements_admin() IS 
'Función administrativa para obtener todos los movimientos. Solo accesible por administradores.';

COMMENT ON FUNCTION get_all_sessions_admin() IS 
'Función administrativa para obtener todas las sesiones. Solo accesible por administradores.';

COMMENT ON FUNCTION get_all_mercadopago_payments_admin() IS 
'Función administrativa para obtener todos los pagos de MercadoPago. Solo accesible por administradores.';

COMMENT ON FUNCTION get_all_subscriptions_admin() IS 
'Función administrativa para obtener todas las suscripciones. Solo accesible por administradores.';
