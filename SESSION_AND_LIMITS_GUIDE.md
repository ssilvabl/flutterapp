# Control de Sesiones y Límites de Transacciones

## Descripción General

Este sistema implementa controles de sesiones activas y límites de transacciones basados en roles de usuario:

### Roles y Límites

| Rol     | Sesiones Máximas | Transacciones Máximas |
|---------|------------------|-----------------------|
| Admin   | 1                | Ilimitadas            |
| Premium | 3                | 3,000                 |
| Free    | 2                | 15                    |

## Configuración en Supabase

### 1. Ejecutar la Migración SQL

Ejecuta el archivo de migración para crear la tabla de sesiones y funciones necesarias:

```bash
db/migrations/20251226_add_payments_movements.sql
```

Este archivo creará:
- Tabla `user_sessions` para rastrear sesiones activas
- Funciones para limpiar sesiones inactivas
- Funciones para obtener conteo de sesiones
- Políticas RLS para proteger los datos de sesiones

### 2. Verificar Políticas RLS

Asegúrate de que las siguientes políticas RLS estén activas:

**Tabla `user_sessions`:**
- `Users can view own sessions` - Permite ver solo sus propias sesiones
- `Users can insert own sessions` - Permite crear sesiones propias
- `Users can update own sessions` - Permite actualizar actividad de sesión
- `Users can delete own sessions` - Permite eliminar sesiones propias

**Tabla `profiles`:**
- Debe incluir el campo `role` (admin, premium, free)

**Tabla `payments`:**
- Debe tener campo `user_id` para contar transacciones por usuario

## Funcionamiento del Sistema

### Control de Sesiones

#### Al Iniciar Sesión:
1. El usuario ingresa email y contraseña
2. El sistema verifica cuántas sesiones activas tiene el usuario
3. Si se excede el límite:
   - Se muestra un diálogo con lista de sesiones activas
   - El usuario puede cerrar sesiones anteriores para continuar
   - Si cancela, la sesión actual se cierra

#### Diálogo de Sesiones Activas:
- Muestra información del dispositivo de cada sesión
- Muestra fecha/hora de última actividad
- Permite cerrar todas las sesiones anteriores de una vez

#### Sesiones Activas:
- Se consideran activas las sesiones con actividad en los últimos 7 días
- Las sesiones inactivas por más de 30 días se pueden limpiar automáticamente

### Control de Límites de Transacciones

#### En la Pantalla Principal:
1. Al cargar, el sistema cuenta las transacciones del usuario
2. Compara el conteo con el límite según el rol
3. Si se alcanza el límite:
   - El botón de agregar se deshabilita
   - Se muestra mensaje "Límite alcanzado (X/Y)"
   - No se pueden crear nuevas transacciones

#### Contador de Transacciones:
- Se muestra bajo el botón de agregar
- Formato: "X / Y transacciones" o "X / Y" (compacto)
- Color rojo cuando se alcanza el límite
- Color gris cuando hay espacio disponible

#### Actualización Automática:
- Se actualiza después de agregar una transacción
- Se actualiza después de eliminar una transacción
- Se actualiza después de editar (no consume cuota adicional)

## Archivos Modificados

### Nuevos Archivos:
1. **`lib/utils/session_manager.dart`** - Gestión de sesiones y límites
   - `checkSessionLimit()` - Verifica límite de sesiones
   - `createSession()` - Crea nueva sesión
   - `removeCurrentSession()` - Elimina sesión actual
   - `checkTransactionLimit()` - Verifica límite de transacciones
   - `getTransactionCount()` - Cuenta transacciones del usuario

2. **`db/migrations/20251226_add_payments_movements.sql`** - Migración SQL
   - Tabla `user_sessions`
   - Funciones de gestión de sesiones
   - Políticas RLS

### Archivos Modificados:
1. **`lib/constants/user_roles.dart`**
   - Agregado `maxActiveSessions` por rol
   - Agregado `maxTransactions` por rol

2. **`lib/screens/login.dart`**
   - Verificación de límite de sesiones al login
   - Diálogo para cerrar sesiones antiguas
   - Creación de sesión al iniciar correctamente

3. **`lib/screens/payments_list.dart`**
   - Verificación de límite de transacciones
   - Deshabilitar botón de agregar cuando se alcanza límite
   - Mostrar contador de transacciones
   - Eliminar sesión al cerrar sesión

## Pruebas

### Probar Control de Sesiones:

1. **Crear usuario con rol Free:**
   ```sql
   UPDATE profiles SET role = 'free' WHERE email = 'test@example.com';
   ```

2. **Iniciar sesión en 2 dispositivos/navegadores diferentes**
   - Primera sesión: OK
   - Segunda sesión: OK
   
3. **Intentar iniciar sesión en un tercer dispositivo**
   - Debe mostrar diálogo de límite alcanzado
   - Debe mostrar lista de 2 sesiones activas
   - Al aceptar, debe cerrar sesiones anteriores y permitir continuar

### Probar Límite de Transacciones:

1. **Crear usuario Free (límite: 15 transacciones):**
   ```sql
   UPDATE profiles SET role = 'free' WHERE email = 'test@example.com';
   ```

2. **Agregar 15 transacciones**
   - Contador debe mostrar 15/15
   - Botón de agregar debe deshabilitarse
   - Mensaje "Límite alcanzado" debe aparecer

3. **Eliminar una transacción**
   - Contador debe mostrar 14/15
   - Botón de agregar debe habilitarse nuevamente

4. **Cambiar rol a Premium:**
   ```sql
   UPDATE profiles SET role = 'premium' WHERE email = 'test@example.com';
   ```
   - Cerrar sesión y volver a iniciar
   - Límite debe ser ahora 3000

## Solución de Problemas

### Error: "No se puede crear sesión"
- Verificar que la tabla `user_sessions` existe
- Verificar políticas RLS en Supabase
- Verificar que el usuario está autenticado

### Error: "Límite de transacciones no se actualiza"
- Verificar campo `user_id` en tabla `payments`
- Verificar que `_checkTransactionLimit()` se llama después de operaciones
- Revisar logs en consola

### Sesiones no se eliminan:
- Ejecutar manualmente función de limpieza:
  ```sql
  SELECT cleanup_inactive_sessions();
  ```

### Contador muestra valores incorrectos:
- Verificar que la consulta de conteo incluye filtro por `user_id`
- Revisar si hay transacciones huérfanas sin `user_id`

## Seguridad

- Las sesiones están protegidas por RLS
- Los usuarios solo pueden ver/modificar sus propias sesiones
- Las transacciones están protegidas por RLS
- El conteo de transacciones usa el `user_id` autenticado

## Mantenimiento

### Limpiar sesiones inactivas (ejecutar periódicamente):
```sql
SELECT cleanup_inactive_sessions();
```

### Ver sesiones activas de un usuario:
```sql
SELECT * FROM user_sessions 
WHERE user_id = 'USER_ID_HERE' 
ORDER BY last_activity DESC;
```

### Ver conteo de transacciones por usuario:
```sql
SELECT user_id, COUNT(*) as transaction_count
FROM payments
GROUP BY user_id
ORDER BY transaction_count DESC;
```
