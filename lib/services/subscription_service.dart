import 'package:supabase_flutter/supabase_flutter.dart';

class SubscriptionService {
  final _supabase = Supabase.instance.client;

  /// Activa una suscripción premium para un usuario
  Future<void> activateSubscription(String userId) async {
    print('📝 SubscriptionService.activateSubscription llamado');
    print('   userId: $userId');
    
    final now = DateTime.now();
    final endDate = now.add(const Duration(days: 30));
    
    print('   subscription_start: ${now.toIso8601String()}');
    print('   subscription_end: ${endDate.toIso8601String()}');

    try {
      final result = await _supabase.from('profiles').update({
        'role': 'premium',
        'subscription_start': now.toIso8601String(),
        'subscription_end': endDate.toIso8601String(),
        'subscription_cancelled': false,
        'updated_at': now.toIso8601String(),
      }).eq('id', userId);
      
      print('✅ Update ejecutado correctamente');
      print('   Resultado: $result');
    } catch (e) {
      print('❌ Error en update: $e');
      rethrow;
    }
  }

  /// Renueva una suscripción existente (30 días más desde la fecha actual de vencimiento)
  Future<void> renewSubscription(String userId) async {
    final profile = await _supabase
        .from('profiles')
        .select('subscription_end')
        .eq('id', userId)
        .single();

    final currentEnd = profile['subscription_end'] as String?;
    DateTime newEndDate;

    if (currentEnd != null) {
      final currentEndDate = DateTime.parse(currentEnd);
      // Si aún no ha vencido, agregar 30 días desde la fecha actual de fin
      if (currentEndDate.isAfter(DateTime.now())) {
        newEndDate = currentEndDate.add(const Duration(days: 30));
      } else {
        // Si ya venció, agregar 30 días desde hoy
        newEndDate = DateTime.now().add(const Duration(days: 30));
      }
    } else {
      // Si no tiene fecha de fin, agregar 30 días desde hoy
      newEndDate = DateTime.now().add(const Duration(days: 30));
    }

    await _supabase.from('profiles').update({
      'role': 'premium',
      'subscription_end': newEndDate.toIso8601String(),
      'subscription_cancelled': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Cancela la suscripción (no elimina, solo marca como cancelada)
  Future<void> cancelSubscription(String userId) async {
    await _supabase.from('profiles').update({
      'subscription_cancelled': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', userId);
  }

  /// Verifica si una suscripción ha vencido y debe renovarse automáticamente
  Future<bool> shouldRenewSubscription(String userId) async {
    final profile = await _supabase
        .from('profiles')
        .select('role, subscription_end, subscription_cancelled')
        .eq('id', userId)
        .single();

    final role = profile['role'] as String?;
    final endDateStr = profile['subscription_end'] as String?;
    final cancelled = profile['subscription_cancelled'] as bool?;

    if (role != 'premium' || endDateStr == null || cancelled == true) {
      return false;
    }

    final endDate = DateTime.parse(endDateStr);
    final now = DateTime.now();

    // Si ya venció y no está cancelada, debe renovarse
    return endDate.isBefore(now);
  }

  /// Procesa el webhook de confirmación de pago de ePayco
  Future<void> handlePaymentConfirmation({
    required String userId,
    required String transactionId,
    required bool isApproved,
    required String paymentMethod,
  }) async {
    if (!isApproved) {
      // Si el pago fue rechazado, no hacer nada
      return;
    }

    // Registrar la transacción en una tabla de pagos (opcional)
    await _supabase.from('subscription_payments').insert({
      'user_id': userId,
      'transaction_id': transactionId,
      'amount': 25000,
      'currency': 'COP',
      'payment_method': paymentMethod,
      'status': 'approved',
      'created_at': DateTime.now().toIso8601String(),
    });

    // Verificar si es una nueva suscripción o renovación
    final profile = await _supabase
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .single();

    if (profile['role'] == 'free') {
      // Nueva suscripción
      await activateSubscription(userId);
    } else {
      // Renovación
      await renewSubscription(userId);
    }
  }
}
