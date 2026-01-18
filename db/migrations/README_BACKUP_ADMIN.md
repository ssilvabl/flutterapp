# Configuración de Backup Completo para Administradores

## Problema
El backup solo exportaba datos del usuario actual debido a las políticas RLS (Row Level Security) de Supabase.

## Solución
Se crearon funciones RPC administrativas que permiten a los administradores obtener TODOS los datos de TODOS los usuarios.

## Pasos de Instalación

### 1. Ejecutar Script SQL en Supabase

Debes ejecutar el archivo SQL de migración en tu base de datos de Supabase:

1. Abre el **SQL Editor** en tu dashboard de Supabase
2. Copia y pega el contenido del archivo:
   ```
   db/migrations/20260113_add_admin_backup_functions.sql
   ```
3. Ejecuta el script completo

### 2. Funciones Creadas

El script crea las siguientes funciones RPC administrativas:

- `get_all_profiles_admin()` - Obtiene todos los perfiles de usuarios
- `get_all_payments_admin()` - Obtiene todos los pagos/cobros
- `get_all_movements_admin()` - Obtiene todos los movimientos
- `get_all_sessions_admin()` - Obtiene todas las sesiones activas
- `get_all_mercadopago_payments_admin()` - Obtiene todos los pagos de MercadoPago
- `get_all_subscriptions_admin()` - Obtiene todas las suscripciones

### 3. Seguridad

**Importante:**
- Solo usuarios con rol `admin` pueden ejecutar estas funciones
- Las funciones usan `SECURITY DEFINER` para bypassear RLS
- Si un usuario no administrador intenta ejecutarlas, recibirá un error

### 4. Verificar Usuario Admin

Asegúrate de que tu usuario tenga el rol de administrador:

```sql
-- Verificar tu rol actual
SELECT role FROM profiles WHERE id = auth.uid();

-- Si necesitas promover a admin (ejecutar como superusuario):
UPDATE profiles SET role = 'admin' WHERE id = 'TU-USER-ID-AQUI';
```

### 5. Uso

Una vez configurado:

1. Abre la app y ve a **Admin Panel**
2. Presiona el botón **"Backup Completo"**
3. La app usará las funciones RPC para obtener TODOS los datos
4. Se generará un archivo SQL con:
   - Estructura completa de todas las tablas
   - TODOS los datos de TODOS los usuarios
   - Índices y políticas RLS
   - Resumen detallado

### 6. Verificación

Para verificar que funciona:

```sql
-- Ejecutar en SQL Editor (como admin)
SELECT * FROM get_all_profiles_admin();
SELECT * FROM get_all_payments_admin();
```

Si ves datos de múltiples usuarios, ¡está funcionando correctamente!

## Estructura del Backup Generado

El backup SQL incluye:

1. **Estructuras de Tablas**
   - profiles
   - payments
   - payments_movements
   - user_sessions
   - mercadopago_payments
   - subscriptions

2. **Índices**
   - Todos los índices optimizados

3. **Políticas RLS**
   - Todas las políticas de seguridad

4. **Datos**
   - TODOS los registros de TODOS los usuarios
   - Formato idempotente (ON CONFLICT DO UPDATE)

5. **Resumen**
   - Conteos de registros por tabla
   - Total de registros exportados
   - Fecha de generación

## Troubleshooting

### Error: "Solo administradores pueden ejecutar esta función"
- Verifica que tu usuario tenga rol `admin` en la tabla profiles

### Error: "function get_all_profiles_admin() does not exist"
- Ejecuta el script SQL de migración en Supabase SQL Editor

### El backup solo muestra mis datos
- Las funciones RPC no están instaladas o no estás usando el rol admin
- Ejecuta el script SQL de migración

### Error de permisos
- Asegúrate de que el script SQL se ejecutó correctamente
- Las funciones deben crearse en el schema `public`
