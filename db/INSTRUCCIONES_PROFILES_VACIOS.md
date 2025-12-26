# 🚨 SOLUCIÓN URGENTE: Tabla Profiles Vacía

## 🐛 Problema
La tabla `profiles` está **completamente vacía** aunque hay usuarios registrados en `auth.users`.

### ¿Por qué pasó esto?
Los usuarios se registraron ANTES de que las políticas RLS correctas estuvieran activas, por lo que:
1. El usuario se creó en `auth.users` ✅
2. Pero el perfil NO se creó en `profiles` ❌

---

## ✅ SOLUCIÓN INMEDIATA (3 pasos)

### PASO 1: Crear Perfiles Faltantes

Ejecuta en **Supabase SQL Editor**:

```sql
-- Ver cuántos usuarios hay en cada tabla
SELECT 
    'auth.users' as tabla,
    COUNT(*) as cantidad
FROM auth.users
UNION ALL
SELECT 
    'profiles' as tabla,
    COUNT(*) as cantidad
FROM profiles;

-- Deshabilitar RLS temporalmente
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- Crear perfiles para todos los usuarios que no lo tienen
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

-- Verificar que se crearon
SELECT * FROM profiles;
```

### PASO 2: Cambiar Rol a Admin

```sql
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'sepagos.email@gmail.com';

-- Verificar
SELECT email, role FROM profiles WHERE email = 'sepagos.email@gmail.com';
```

Deberías ver: `sepagos.email@gmail.com | admin`

### PASO 3: Crear Trigger Automático (Importante)

Para que **futuros usuarios** creen su perfil automáticamente:

```sql
-- Función que crea el perfil
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario'),
    'free',
    NEW.created_at
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger que se activa al registrar usuario
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

---

## 🧪 Verificación

### 1. Ver todos los perfiles:
```sql
SELECT 
    email,
    full_name,
    role,
    created_at
FROM profiles 
ORDER BY created_at DESC;
```

### 2. Verificar que eres admin:
```sql
SELECT email, role 
FROM profiles 
WHERE email = 'sepagos.email@gmail.com';
```

Debe mostrar: `role = 'admin'`

### 3. Probar en la app:
1. Cierra y reinicia la app
2. Inicia sesión
3. Abre el menú hamburguesa
4. **Deberías ver** el botón "Administración" 🎉
5. Haz clic y verás la lista de usuarios

---

## 🔍 ¿Por Qué el Trigger es Necesario?

### ❌ SIN Trigger:
```
Usuario se registra → Se crea en auth.users → Código Flutter intenta crear perfil → RLS lo bloquea → ❌ No hay perfil
```

### ✅ CON Trigger:
```
Usuario se registra → Se crea en auth.users → Trigger automático crea perfil → ✅ Perfil creado
```

El trigger usa `SECURITY DEFINER` que le permite saltarse las políticas RLS.

---

## 📊 Scripts Disponibles

He creado varios archivos SQL en la carpeta `db/`:

1. **SOLUCION_RAPIDA_PROFILES.sql** - Script completo todo-en-uno
2. **20251226_fix_missing_profiles.sql** - Análisis y corrección paso a paso
3. **20251226_create_profile_trigger.sql** - Solo el trigger automático

---

## 🎯 Orden de Ejecución Recomendado

```sql
-- 1. Crear perfiles faltantes (PASO 1)
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
INSERT INTO profiles (id, email, full_name, role)
SELECT au.id, au.email, 
       COALESCE(au.raw_user_meta_data->>'full_name', 'Usuario'),
       'free'
FROM auth.users au
LEFT JOIN profiles p ON au.id = p.id
WHERE p.id IS NULL;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 2. Hacer admin (PASO 2)
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'sepagos.email@gmail.com';

-- 3. Crear trigger (PASO 3)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (NEW.id, NEW.email, 
          COALESCE(NEW.raw_user_meta_data->>'full_name', 'Usuario'),
          'free');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

---

## 🚨 Si Algo Sale Mal

### Error: "duplicate key value violates unique constraint"
Ya existe el perfil. Verifica:
```sql
SELECT * FROM profiles WHERE email = 'sepagos.email@gmail.com';
```

### Error: "permission denied for table profiles"
Estás usando el usuario equivocado. Usa el **service_role key** en Supabase SQL Editor (ya está configurado por defecto).

### La tabla sigue vacía después del INSERT
Verifica que los usuarios existan:
```sql
SELECT id, email FROM auth.users;
```

### El trigger no se crea
Verifica permisos:
```sql
SELECT current_user;
-- Debe mostrar: 'postgres' o 'supabase_admin'
```

---

## 🎉 Después de Esto

1. ✅ Todos los usuarios existentes tendrán perfil
2. ✅ Tu usuario será admin
3. ✅ Futuros usuarios crearán perfil automáticamente
4. ✅ Podrás acceder al panel de administración
5. ✅ Podrás cambiar roles desde la app

---

## 🔄 Alternativa: Eliminar Todo y Empezar de Cero

Si prefieres empezar limpio:

```sql
-- ⚠️ ESTO BORRA TODO
DELETE FROM profiles;
DELETE FROM payments;
-- No puedes borrar auth.users directamente desde SQL
-- Debes hacerlo desde: Authentication → Users → Delete

-- Luego ejecuta el trigger y regístrate de nuevo
```

---

## 📞 Resumen para el Usuario

1. **Ejecuta el script del PASO 1** para crear perfiles faltantes
2. **Ejecuta el PASO 2** para hacerte admin
3. **Ejecuta el PASO 3** para crear el trigger
4. **Reinicia la app** y listo ✅

Todo debería funcionar después de esto.
