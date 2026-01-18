/// Configuración de Mercado Pago para integración de pagos
class MercadoPagoConfig {
  // MODO DE PRUEBA: true = activa suscripción sin pagar, false = usa Mercado Pago
  static const bool demoMode = false;
  
  // Credenciales de Mercado Pago - PRODUCCIÓN
  static const String publicKey = 'APP_USR-1fecee2f-d4d3-4042-8acf-bed9ecca12e8';
  static const String accessToken = 'APP_USR-144222439625427-010300-5fca498f485a021a8ef6d2c5d9392b7f-1330332632';
  
  // Configuración del producto
  static const String subscriptionName = 'Suscripción Premium Sepagos - 30 días';
  static const String subscriptionDescription = 'Plan Premium - 3.000 registros y 3 dispositivos por 30 días';
  static const double subscriptionPrice = 25000.0; // COP
  
  // API Configuration
  static const String apiBaseUrl = 'https://api.mercadopago.com';
  
  // Notification URL (webhook) - Por ahora vacío, se configurará cuando tengas backend
  static const String? notificationUrl = null;
  
  // Para Android: usar deep links
  static const String successUrl = 'sepagos://payment/success';
  static const String failureUrl = 'sepagos://payment/failure'; 
  static const String pendingUrl = 'sepagos://payment/pending';
}

