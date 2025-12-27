-- =====================================================
-- MIGRATION: Add interface_preference to profiles
-- =====================================================
-- Agrega un campo para guardar la preferencia de interfaz del usuario
-- Valores: 'prestamista', 'personal', 'inversionista' o NULL (para nuevos usuarios)

-- Agregar columna interface_preference (permite NULL para nuevos usuarios)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS interface_preference TEXT DEFAULT NULL;

-- Crear índice para optimizar consultas
CREATE INDEX IF NOT EXISTS idx_profiles_interface_preference 
ON profiles(interface_preference);

-- Agregar constraint para validar valores cuando no sea NULL
ALTER TABLE profiles 
ADD CONSTRAINT check_interface_preference 
CHECK (interface_preference IS NULL OR interface_preference IN ('prestamista', 'personal', 'inversionista'));

-- NO actualizar registros existentes - dejarlos NULL para que elijan en el login
-- UPDATE profiles 
-- SET interface_preference = 'prestamista' 
-- WHERE interface_preference IS NULL;

-- Verificar que se creó correctamente
SELECT 
    column_name, 
    data_type, 
    column_default,
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'profiles' 
AND column_name = 'interface_preference';
