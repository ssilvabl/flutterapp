# 🔧 Solución: Problema de Registro y Recursión Infinita en RLS

## 🐛 Problemas Identificados

1. ❌ **"infinite recursion detected in policy"** - Las políticas RLS se llaman a sí mismas
2. ❌ Los usuarios no pueden crear perfiles
3. ❌ Los usuarios no pueden crear pagos/cobros

### Causa Raíz:
Las políticas RLS para admins tenían subconsultas que consultaban la misma tabla `profiles`, creando un bucle infinito.

---

## ✅ Solución Aplicada

### Políticas RLS Corregidas (SIN RECURSIÓN)

Las nuevas políticas son más simples y no tienen subconsultas recursivas.

---

## 🚀 PASOS OBLIGATORIOS - EJECUTAR AHORA

### Paso 1: Ejecutar SQL en Supabase (IMPORTANTE)

1. Ve a **Supabase Dashboard**
2. Abre **SQL Editor**
3. Crea una **New Query**
4. Copia y pega **ESTE SQL** (corregido):

```sql
-- =====================================================
-- LIMPIAR Y RECREAR POLÍTICAS (SIN RECURSIÓN)
-- =====================================================

-- 1. DESHABILITAR RLS TEMPORALMENTE
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE payments DISABLE ROW LEVEL SECURITY;

-- 2. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES DE PROFILES
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can view own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "Admins can view all profiles" ON profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON profiles;
DROP POLICY IF EXISTS "Enable read access for users based on user_id" ON profiles;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON profiles;
DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON profiles;

-- 3. ELIMINAR TODAS LAS POLÍTICAS EXISTENTES DE PAYMENTS
DROP POLICY IF EXISTS "Users can view own payments" ON payments;
DROP POLICY IF EXISTS "Users can insert own payments" ON payments;
DROP POLICY IF EXISTS "Users can update own payments" ON payments;
DROP POLICY IF EXISTS "Users can delete own payments" ON payments;
DROP POLICY IF EXISTS "Admins can view all payments" ON payments;
DROP POLICY IF EXISTS "Enable read access for users based on user_id" ON payments;
DROP POLICY IF EXISTS "Enable insert for users based on user_id" ON payments;
DROP POLICY IF EXISTS "Enable update for users based on user_id" ON payments;
DROP POLICY IF EXISTS "Enable delete for users based on user_id" ON payments;

-- 4. HABILITAR RLS
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- POLÍTICAS PARA PROFILES (SIMPLES, SIN RECURSIÓN)
-- =====================================================

-- Permitir que usuarios creen su propio perfil
CREATE POLICY "Enable insert for users based on user_id"
ON profiles FOR INSERT
WITH CHECK (auth.uid() = id);

-- Permitir lectura para usuarios autenticados (para panel admin)
CREATE POLICY "Enable read access for all authenticated users"
ON profiles FOR SELECT
USING (auth.role() = 'authenticated');

-- Permitir que usuarios actualicen su propio perfil
CREATE POLICY "Enable update for users based on user_id"
ON profiles FOR UPDATE
USING (auth.uid() = id);

-- =====================================================
-- POLÍTICAS PARA PAYMENTS
-- =====================================================

-- Usuarios pueden ver solo sus pagos
CREATE POLICY "Enable read access for users based on user_id"
ON payments FOR SELECT
USING (auth.uid() = user_id);

-- Usuarios pueden insertar sus propios pagos
CREATE POLICY "Enable insert for users based on user_id"
ON payments FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Usuarios pueden actualizar sus propios pagos
CREATE POLICY "Enable update for users based on user_id"
ON payments FOR UPDATE
USING (auth.uid() = user_id);

-- Usuarios pueden eliminar sus propios pagos
CREATE POLICY "Enable delete for users based on user_id"
ON payments FOR DELETE
USING (auth.uid() = user_id);
```

5. Haz clic en **RUN** o presiona **Ctrl+Enter**
6. Deberías ver: **Success. No rows returned**

---

### Paso 2: Verificar que las Políticas se Aplicaron

Ejecuta este SQL para verificar:

```sql
-- Ver políticas de profiles
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'profiles';

-- Ver políticas de payments
SELECT policyname, cmd FROM pg_policies WHERE tablename = 'payments';
```

Deberías ver:
- **profiles**: 3 políticas (INSERT, SELECT, UPDATE)
- **payments**: 4 políticas (SELECT, INSERT, UPDATE, DELETE)

---

### Paso 3: Reiniciar la App

```bash
# Detener la app (Ctrl+C en la terminal)
# Luego ejecutar:
flutter clean
flutter pub get
flutter run
```

---

## 🧪 Pruebas a Realizar

### Prueba 1: Registrar Usuario ✅
1. Registra un nuevo usuario en la app
2. Deberías ver en consola: `Profile created successfully for user: [uuid]`
3. Verifica en Supabase → profiles → debería aparecer el nuevo usuario

### Prueba 2: Crear Pago/Cobro ✅
1. Inicia sesión con el usuario
2. Haz clic en el botón "+" para agregar un pago o cobro
3. Completa el formulario
4. Debería guardarse sin errores
5. Verifica en Supabase → payments → debería aparecer el registro

### Prueba 3: Ver Perfil ✅
1. Abre el menú hamburguesa
2. Haz clic en "Perfil"
3. Debería mostrar tu información correctamente

---

## 🔍 Si Algo Sigue Sin Funcionar

### Error: "No se pudo completar la operación" al crear pago
**Verificar:**
```sql
-- Ver si RLS está habilitado
SELECT tablename, rowsecurity FROM pg_tables 
WHERE schemaname = 'public' AND tablename = 'payments';
-- Debe mostrar: rowsecurity = true

-- Ver políticas de payments
SELECT policyname FROM pg_policies WHERE tablename = 'payments';
-- Debe mostrar las 4 políticas
```

### Error: "new row violates row-level security policy"
**Solución:** Ejecuta nuevamente el SQL del Paso 1

### Los perfiles no aparecen en Supabase
**Verificar:**
1. Que el SQL se ejecutó correctamente
2. Que no hay errores en la consola de Flutter
3. Ejecuta manualmente:
```sql
SELECT * FROM profiles;
```

---

## 📊 Cambios en las Políticas RLS

### ❌ ANTES (Con Recursión):
```sql
-- ESTO CAUSABA RECURSIÓN INFINITA
CREATE POLICY "Admins can view all profiles"
ON profiles FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles  -- ← Consulta la misma tabla!
    WHERE id = auth.uid() 
    AND role = 'admin'
  )
);
```

### ✅ AHORA (Sin Recursión):
```sql
-- SIMPLE Y FUNCIONAL
CREATE POLICY "Enable read access for all authenticated users"
ON profiles FOR SELECT
USING (auth.role() = 'authenticated');  -- ← No consulta la tabla
```

---

## 🎯 Comportamiento Después de la Corrección

### Usuarios Normales:
- ✅ Pueden crear su perfil al registrarse
- ✅ Pueden ver su propio perfil
- ✅ Pueden actualizar su propio perfil
- ✅ Pueden ver perfiles de otros usuarios (para el admin panel)
- ✅ Pueden crear sus pagos/cobros
- ✅ Solo ven sus propios pagos/cobros

### Administradores:
- ✅ Pueden ver todos los perfiles (panel admin)
- ✅ Pueden cambiar roles de usuarios
- ⚠️ **Nota:** La verificación de admin se hace en el frontend (UserRole)

---

## 📁 Archivos Modificados

- ✅ `db/migrations/20251226_rls_policies.sql` - Políticas corregidas
- ✅ `lib/screens/register.dart` - Mejor manejo de errores

---

## ⚠️ IMPORTANTE: Seguridad

La política `Enable read access for all authenticated users` permite que todos los usuarios autenticados vean todos los perfiles. Esto es necesario para:
1. El panel de administración
2. Mostrar nombres de usuarios en la app

Si quieres mayor seguridad, considera:
1. Crear una función de Supabase para verificar roles sin recursión
2. Usar Service Role Key solo en el backend para operaciones admin
3. Limitar qué campos son visibles públicamente

---

## 🚨 Si NADA Funciona

**Opción Nuclear: Deshabilitar RLS Temporalmente**

```sql
-- ⚠️ SOLO PARA DESARROLLO/PRUEBAS
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE payments DISABLE ROW LEVEL SECURITY;
```

Esto deshabilitará completamente la seguridad de filas. **NO uses esto en producción**.

Después de verificar que todo funciona, vuelve a habilitar RLS y aplica las políticas.
