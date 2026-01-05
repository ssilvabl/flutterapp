# Implementación de Mercado Pago

## Configuración Completada

### Archivos Creados

1. **lib/constants/mercadopago_config.dart**
   - Contiene las credenciales de prueba
   - Public Key: APP_USR-a4237fad-82a4-4dee-8ebe-70b019992e05
   - Access Token: APP_USR-1381022203053777-122901-289c7b7c379248bc6572ae74a632e469-1339969997
   - Configuración del producto: \$25.000 COP/mes
   - URLs de deep links para success/failure/pending

2. **lib/services/mercadopago_service.dart**
   - `createPaymentPreference()`: Crea una preferencia de pago en Mercado Pago
   - `getPaymentInfo()`: Verifica el estado de un pago específico
   - Usa la API REST de Mercado Pago

3. **lib/screens/subscription.dart**
   - Actualizado para usar MercadoPagoService
   - Importa `url_launcher` para abrir en navegador externo
   - Deep links configurados para /payment/success, /payment/failure, /payment/pending
   - Activa automáticamente la suscripción al recibir pago exitoso

## Flujo de Pago

1. Usuario hace clic en "Suscribirse a Premium"
2. App muestra diálogo de confirmación
3. App crea una preferencia de pago en Mercado Pago API
4. Mercado Pago devuelve URL de checkout (`init_point`)
5. App abre la URL en navegador externo
6. Usuario completa el pago en Mercado Pago
7. Mercado Pago redirige a deep link según resultado:
   - `sepagos://payment/success` → Activa suscripción
   - `sepagos://payment/failure` → Muestra error
   - `sepagos://payment/pending` → Muestra mensaje de pendiente
8. App detecta deep link y procesa respuesta

## Deep Links Configurados

En AndroidManifest.xml ya deben estar configurados:
- Scheme: `sepagos`
- Host: `payment`
- Paths: `/success`, `/failure`, `/pending`

## API de Mercado Pago

### Crear Preferencia de Pago
```
POST https://api.mercadopago.com/checkout/preferences
Authorization: Bearer {access_token}
Content-Type: application/json
```

Body:
```json
{
  "items": [{
    "title": "Suscripción Premium",
    "quantity": 1,
    "currency_id": "COP",
    "unit_price": 25000
  }],
  "payer": {
    "email": "usuario@email.com",
    "name": "Nombre Usuario"
  },
  "back_urls": {
    "success": "sepagos://payment/success",
    "failure": "sepagos://payment/failure",
    "pending": "sepagos://payment/pending"
  },
  "external_reference": "SUB-{userId}-{timestamp}"
}
```

Respuesta:
```json
{
  "id": "12345678-abcd-...",
  "init_point": "https://www.mercadopago.com.co/checkout/v1/redirect?pref_id=..."
}
```

## Tarjetas de Prueba (Colombia)

### Mastercard Aprobada
- Número: 5474 9254 3267 0366
- CVV: 123
- Fecha: Cualquier fecha futura
- Nombre: APRO

### Visa Rechazada
- Número: 4013 5406 8274 6260
- CVV: 123
- Fecha: Cualquier fecha futura
- Nombre: OTHE (Other Error)

### Visa Pendiente
- Número: 4009 1753 3280 6001
- CVV: 123
- Fecha: Cualquier fecha futura
- Nombre: CONT (Contingencia)

## Testing

### Probar Pago Exitoso
1. Ir a pantalla de Suscripción
2. Hacer clic en "Suscribirse a Premium"
3. Confirmar en diálogo
4. Esperar redirección a Mercado Pago
5. Usar tarjeta de prueba APRO (Mastercard)
6. Completar formulario con datos ficticios
7. Confirmar pago
8. Mercado Pago redirige a `sepagos://payment/success`
9. App activa suscripción automáticamente
10. Verificar que role cambia a 'premium' y se muestran fechas

### Probar Pago Rechazado
1. Seguir mismo flujo
2. Usar tarjeta OTHE (Visa rechazada)
3. Mercado Pago redirige a `sepagos://payment/failure`
4. App muestra mensaje "El pago no fue completado"

## Producción

### Para pasar a producción:

1. Obtener credenciales de producción en Mercado Pago Developers
2. Actualizar `mercadopago_config.dart`:
   ```dart
   static const bool testMode = false;
   static const String publicKey = 'APP_USR-xxxxx-prod';
   static const String accessToken = 'APP_USR-xxxxx-prod';
   ```

3. **IMPORTANTE**: El Access Token NO debe estar en el código de producción
   - Mover la lógica de crear preferencias a un backend/Cloud Function
   - El backend debe crear la preferencia y devolver solo el `init_point`
   - Nunca exponer el Access Token en la app

4. Configurar webhooks para notificaciones IPN:
   - URL: https://tu-backend.com/webhooks/mercadopago
   - Eventos: payment, merchant_order
   - El webhook debe verificar el pago y activar suscripción en Supabase

5. Actualizar `notification_url` en config con tu webhook real

## Seguridad

⚠️ **IMPORTANTE PARA PRODUCCIÓN**: 
- El Access Token actual está en el código para testing
- En producción, NUNCA incluyas el Access Token en la app
- Usa un backend para crear preferencias de pago
- Verifica pagos mediante webhooks, no solo deep links
- Los deep links pueden ser falsificados, usa webhooks para confirmación real

## Webhooks (Para Implementar)

Mercado Pago enviará notificaciones POST a tu webhook:
```
POST https://tu-backend.com/webhooks/mercadopago
Content-Type: application/json

{
  "action": "payment.created",
  "data": {
    "id": "12345678"
  }
}
```

Tu backend debe:
1. Recibir notificación
2. Obtener detalles del pago: `GET /v1/payments/{id}`
3. Verificar estado == 'approved'
4. Extraer `external_reference` (contiene userId)
5. Activar suscripción en Supabase usando subscription_service
6. Guardar registro en tabla subscription_payments

## Base de Datos

La tabla `subscription_payments` ya está creada y lista para registrar transacciones:
- transaction_id (del payment_id de Mercado Pago)
- user_id
- amount (25000)
- currency ('COP')
- payment_method ('credit_card', 'debit_card', etc.)
- status ('approved', 'rejected', 'pending')

## Referencias

- Documentación Mercado Pago: https://www.mercadopago.com.co/developers
- API Reference: https://www.mercadopago.com.co/developers/es/reference
- Testing: https://www.mercadopago.com.co/developers/es/docs/checkout-pro/additional-content/test-cards
