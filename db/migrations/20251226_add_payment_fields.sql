-- =====================================================
-- TRIGGER AUTOMÁTICO + CREAR PERFILES FALTANTES
-- =====================================================
-- Este script hace 2 cosas:
-- 1. Crea perfiles para usuarios existentes sin perfil
-- 2. Crea un trigger para que FUTUROS usuarios tengan perfil automáticamente

-- PARTE 1: Crear perfiles faltantes (USUARIOS EXISTENTES)
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

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

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- PARTE 2: Crear función del trigger (FUTUROS USUARIOS)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger 
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario'),
    'free'
  );
  RETURN NEW;
EXCEPTION
  WHEN others THEN
    -- Si falla, no bloquear el registro del usuario
    RETURN NEW;
END;
$$;

-- PARTE 3: Crear trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW 
  EXECUTE FUNCTION public.handle_new_user();

-- PARTE 4: Verificar que el trigger se creó
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

-- PARTE 5: Verificar perfiles existentes
SELECT 
    COUNT(*) as "Perfiles creados"
FROM profiles;

-- Si el resultado del trigger muestra datos, está activo ✅
-- Ahora TODOS los nuevos usuarios crearán perfil automáticamente
