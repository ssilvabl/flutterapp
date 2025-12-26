# Resumen de Cambios - Panel de Administración

## ✅ Funcionalidades Implementadas

### 1. Botón de Administración en el Menú (Solo para Admins)
**Estado:** ✅ Completado

Se agregó un botón "Administración" en el menú hamburguesa que solo es visible para usuarios con rol `admin`.

**Archivos modificados:**
- [lib/screens/payments_list.dart](lib/screens/payments_list.dart)
  - Agregado import de `user_roles.dart` y `admin.dart`
  - Agregada variable de estado `_userRole`
  - Agregado método `_loadUserRole()` para cargar el rol del usuario
  - Modificado el `Drawer` para incluir el botón de Administración condicionalmente

**Ubicación del botón:**
- Menú hamburguesa → "Administración" (solo visible para admins)
- Ícono: `admin_panel_settings`

---

### 2. Pantalla de Administración
**Estado:** ✅ Completado

Se creó una pantalla completa de administración con una tabla de usuarios.

**Archivo creado:**
- [lib/screens/admin.dart](lib/screens/admin.dart)

**Características de la pantalla:**

#### Tabla de Usuarios con las siguientes columnas:

1. **Usuario**: Nombre completo y empresa (si aplica)
2. **Email**: Correo electrónico del usuario
3. **Rol**: Badge con color según el rol
   - Admin: Rojo
   - Premium: Amarillo/Ámbar
   - Free: Gris
4. **Registro**: Fecha de registro (DD/MM/YYYY)
5. **Pagos**: Número de pagos con ícono de flecha hacia arriba (rojo)
6. **Cobros**: Número de cobros con ícono de flecha hacia abajo (verde)
7. **Acciones**: Botón de tres puntos verticales

#### Funcionalidades:
- ✅ Scroll horizontal para la tabla en pantallas pequeñas
- ✅ Pull to refresh para recargar la lista
- ✅ Carga de datos desde Supabase
- ✅ Conteo automático de pagos y cobros por usuario

---

### 3. Menú de Acciones (Tres puntos)
**Estado:** ✅ Completado

Al hacer clic en el botón de tres puntos de cada usuario, se muestra un menú con las siguientes opciones:

#### a) Reenviar Correo de Recuperación
- Muestra diálogo de confirmación con el email del usuario
- Envía correo de recuperación usando `auth.resetPasswordForEmail()`
- Muestra mensaje de éxito o error
- El usuario recibirá un enlace para restablecer su contraseña

#### b) Cambiar Rol
- Muestra diálogo con opciones de rol mediante RadioButtons
- Tres opciones disponibles:
  - **Admin**: Acceso completo al sistema
  - **Premium**: Funciones premium
  - **Free**: Acceso básico
- Actualiza el rol en la base de datos
- Recarga la lista de usuarios automáticamente
- Muestra mensaje de éxito o error

---

## 📊 Estructura de Datos

### Clase UserInfo
```dart
class UserInfo {
  final String id;
  final String email;
  final String? fullName;
  final String? company;
  final String role;
  final DateTime createdAt;
  final int totalPayments;
  final int totalCollections;
}
```

---

## 🔄 Flujo de Datos

### Carga de Usuarios:
1. Se obtienen todos los perfiles desde `profiles` table
2. Para cada perfil:
   - Se obtiene el email
   - Se cuentan los pagos (type = 'pago')
   - Se cuentan los cobros (type = 'cobro')
3. Se crea un objeto `UserInfo` con toda la información
4. Se muestra en la tabla

### Cambio de Rol:
1. Admin selecciona un nuevo rol
2. Se actualiza en la tabla `profiles`
3. Se recarga la lista
4. El usuario afectado verá el cambio al recargar su sesión

---

## 🗄️ Cambios en Base de Datos

### Migración Actualizada
**Archivo:** [db/migrations/20251226_add_user_roles.sql](db/migrations/20251226_add_user_roles.sql)

Se agregó:
```sql
-- Add email column to profiles table for admin access
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS email TEXT;
```

**Nota:** Ejecutar esta migración en Supabase antes de usar el panel de administración.

---

## 📝 Cambios en el Registro

**Archivo modificado:** [lib/screens/register.dart](lib/screens/register.dart)

Ahora al registrar un nuevo usuario se guarda:
- `id`: ID del usuario
- `full_name`: Nombre completo
- `email`: Correo electrónico (NUEVO)
- `role`: 'free' por defecto

Esto permite que el panel de administración muestre los emails correctamente.

---

## 🎨 Interfaz Visual

### Colores por Rol:
- **Admin**: 
  - Background: `Colors.red.shade100`
  - Text: `Colors.red`
  - Icon: `admin_panel_settings`

- **Premium**: 
  - Background: `Colors.amber.shade100`
  - Text: `Colors.amber`
  - Icon: `star`

- **Free**: 
  - Background: `Colors.grey.shade300`
  - Text: `Colors.grey`
  - Icon: `person`

### Iconos:
- Pagos: Flecha hacia arriba (roja)
- Cobros: Flecha hacia abajo (verde)
- Acciones: Tres puntos verticales

---

## 🚀 Cómo Usar

### Para Probar el Panel de Administración:

1. **Crear un usuario administrador:**
   ```sql
   -- En Supabase SQL Editor
   UPDATE profiles 
   SET role = 'admin' 
   WHERE email = 'tu-email@ejemplo.com';
   ```

2. **Iniciar sesión** con la cuenta de administrador

3. **Abrir el menú hamburguesa** en la lista de pagos/cobros

4. **Hacer clic en "Administración"**

5. **Ver la lista de usuarios** con toda la información

6. **Hacer clic en el botón de tres puntos** de cualquier usuario para:
   - Reenviar correo de recuperación
   - Cambiar su rol

---

## ⚠️ Consideraciones de Seguridad

### Row Level Security (RLS)
Asegúrate de configurar políticas de seguridad en Supabase:

```sql
-- Política para que admins puedan ver todos los perfiles
CREATE POLICY "Admins can view all profiles"
ON profiles FOR SELECT
USING (
  auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'admin'
  )
);

-- Política para que admins puedan actualizar roles
CREATE POLICY "Admins can update profiles"
ON profiles FOR UPDATE
USING (
  auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'admin'
  )
);

-- Política para que admins puedan ver todos los pagos
CREATE POLICY "Admins can view all payments"
ON payments FOR SELECT
USING (
  auth.uid() IN (
    SELECT id FROM profiles WHERE role = 'admin'
  )
);
```

---

## 📋 Pasos Siguientes Recomendados

1. **Configurar RLS** en Supabase (ver sección anterior)
2. **Ejecutar la migración** SQL actualizada
3. **Crear al menos un usuario admin** para probar
4. **Probar todas las funcionalidades**:
   - Ver lista de usuarios
   - Reenviar correo de recuperación
   - Cambiar roles
5. **Considerar agregar**:
   - Filtros de búsqueda en la tabla de usuarios
   - Paginación para muchos usuarios
   - Exportar lista de usuarios a CSV/PDF
   - Estadísticas generales del sistema
   - Logs de acciones administrativas

---

## 📁 Archivos Creados/Modificados

### Nuevos archivos:
- `lib/screens/admin.dart` - Pantalla de administración completa

### Archivos modificados:
- `lib/screens/payments_list.dart` - Agregado botón de administración en menú
- `lib/screens/register.dart` - Guardado de email en profiles
- `db/migrations/20251226_add_user_roles.sql` - Agregada columna email

---

## 🐛 Solución de Problemas

### El botón de Administración no aparece:
- Verifica que tu usuario tenga rol 'admin' en la tabla profiles
- Asegúrate de que la migración SQL se ejecutó correctamente

### Los emails aparecen como "N/A":
- Ejecuta la migración SQL actualizada
- Los nuevos usuarios mostrarán el email correctamente
- Para usuarios existentes, puedes actualizar manualmente:
  ```sql
  UPDATE profiles 
  SET email = (SELECT email FROM auth.users WHERE id = profiles.id);
  ```

### Error al reenviar correo de recuperación:
- Verifica la configuración de email en Supabase
- Asegúrate de que el email del usuario es válido

### Error al cambiar roles:
- Verifica las políticas RLS en Supabase
- Asegúrate de que el admin tiene permisos de UPDATE en la tabla profiles

---

## ✨ Características Destacadas

- ✅ Solo visible para administradores
- ✅ Tabla completa con toda la información relevante
- ✅ Contadores automáticos de pagos y cobros
- ✅ Reenvío de correos de recuperación
- ✅ Cambio de roles con interfaz intuitiva
- ✅ Pull to refresh
- ✅ Responsive (scroll horizontal en móviles)
- ✅ Mensajes de confirmación y error claros
- ✅ Recarga automática después de cambios
