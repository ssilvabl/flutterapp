/// Configuración de Mercado Pago para integración de pagos
class MercadoPagoConfig {
  // MODO DE PRUEBA: true = activa suscripción sin pagar, false = usa Mercado Pago
  static const bool demoMode = false;
  
  // Credenciales de Mercado Pago - Checkout Pro
  static const String publicKey = 'APP_USR-17d55c5f-9950-41d8-adc3-2a94eb79b913';
  static const String accessToken = 'APP_USR-590060161349995-010300-f404f4724550fbe2e8a4ce718cedaef7-1339969997';
  
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
