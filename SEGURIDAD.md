# Guía de Seguridad - Sepagos App

## ✅ Medidas de Seguridad Implementadas

### 1. **Ofuscación de Credenciales**
- Las credenciales de Supabase y Mercado Pago están codificadas en Base64
- No se almacenan en texto plano en el código
- Se decodifican en tiempo de ejecución

### 2. **Protección en Git**
El `.gitignore` protege:
- Archivos de firma de Android (`.jks`, `.keystore`)
- Archivos de configuración local (`key.properties`)
- Variables de entorno (`.env`)
- Configuraciones de servicios (`google-services.json`)

### 3. **ProGuard (Opcional)**
- Configurado pero desactivado por defecto
- Puede activarse para ofuscar el código compilado
- Protege las clases de configuración sensibles

### 4. **Permisos de Android**
- Solo los permisos necesarios en el AndroidManifest
- `INTERNET` y `ACCESS_NETWORK_STATE` únicamente

## 🔐 Seguridad de Supabase

### La Anon Key es Segura para Clientes
La `anonKey` de Supabase está **diseñada** para ser pública porque:
1. ✅ Solo permite operaciones autorizadas por RLS (Row Level Security)
2. ✅ No puede acceder directamente a la base de datos
3. ✅ Todas las operaciones pasan por las políticas de seguridad

### Row Level Security (RLS)
**CRÍTICO**: Asegúrate de que tienes RLS habilitado en todas tus tablas:

```sql
-- Ejemplo: Verificar RLS en una tabla
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Ejemplo: Política para que usuarios solo vean sus propios datos
CREATE POLICY "Users can view own profile"
ON profiles FOR SELECT
USING (auth.uid() = user_id);
```

## 🔒 Recomendaciones Adicionales

### Para Producción:
1. **Habilita ProGuard**: 
   - En `android/app/build.gradle` cambia `minifyEnabled false` a `true`
   - Esto ofuscará el código Java/Kotlin compilado

2. **Firma la APK con clave privada**:
   ```bash
   # Generar keystore
   keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

3. **Variables de Entorno** (Opcional para mayor seguridad):
   - Usar paquete `flutter_dotenv`
   - Mantener archivo `.env` fuera de Git
   - Inyectar variables en CI/CD

4. **Rotar Credenciales Periódicamente**:
   - Si sospechas compromiso de seguridad
   - Regenerar tokens en Mercado Pago/Supabase

5. **Monitoreo**:
   - Revisar logs de Supabase regularmente
   - Configurar alertas en Mercado Pago

## ⚠️ Nunca Hagas Esto

❌ No subas a Git público:
- Archivos `.jks` o `.keystore`
- `key.properties`
- Service Account Keys de Google
- Tokens de acceso privados

❌ No uses:
- `service_role` key de Supabase en el cliente
- Access Tokens privados de Mercado Pago en el código del cliente

## 📱 Seguridad en el APK Release

El APK release tiene:
- ✅ Credenciales ofuscadas (Base64)
- ✅ Código Dart compilado (no legible)
- ✅ RLS protegiendo la base de datos
- ✅ Permisos mínimos necesarios

### ¿Es 100% Seguro?
**No**, ninguna app cliente es 100% segura porque:
- Un atacante avanzado puede extraer credenciales del APK
- **Por eso es CRÍTICO tener RLS habilitado en Supabase**
- Las políticas RLS son tu verdadera línea de defensa

## 🛡️ Conclusión

La seguridad real de tu app depende de:
1. **RLS correctamente configurado** en Supabase ⭐⭐⭐
2. Validación server-side de pagos de Mercado Pago
3. Ofuscación de credenciales (dificulta, no previene)
4. Monitoreo y respuesta rápida a incidentes

**La anon key puede estar en el cliente, las RLS policies son tu protección.**
