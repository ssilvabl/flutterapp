import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/mercadopago_config.dart';

class MercadoPagoService {
  /// Crea una preferencia de pago en Mercado Pago
  /// Retorna la URL de checkout para que el usuario complete el pago
  Future<String> createPaymentPreference({
    required String userId,
    required String userEmail,
    required String userName,
  }) async {
    final url = Uri.parse('${MercadoPagoConfig.apiBaseUrl}/checkout/preferences');
    
    // Crear referencia única
    final externalReference = 'SUB-$userId-${DateTime.now().millisecondsSinceEpoch}';
    
    // Preparar los datos de la preferencia según documentación oficial
    final Map<String, dynamic> preferenceData = {
      'items': [
        {
          'title': MercadoPagoConfig.subscriptionName,
          'description': MercadoPagoConfig.subscriptionDescription,
          'quantity': 1,
          'currency_id': 'COP',
          'unit_price': MercadoPagoConfig.subscriptionPrice,
        }
      ],
      'payer': {
        'email': userEmail,
        'name': userName,
      },
      'back_urls': {
        'success': MercadoPagoConfig.successUrl,
        'failure': MercadoPagoConfig.failureUrl,
        'pending': MercadoPagoConfig.pendingUrl,
      },
      'auto_return': 'approved',
      'external_reference': externalReference,
      'statement_descriptor': 'SEPAGOS',
    };
    
    // Agregar notification_url solo si está configurado
    if (MercadoPagoConfig.notificationUrl != null) {
      preferenceData['notification_url'] = MercadoPagoConfig.notificationUrl;
    }

    try {
      print('🔵 Creando preferencia de pago en Mercado Pago...');
      print('📧 Email: $userEmail');
      print('👤 User ID: $userId');
      print('📝 Datos enviados: ${json.encode(preferenceData)}');
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer ${MercadoPagoConfig.accessToken}',
          'Content-Type': 'application/json',
        },
        body: json.encode(preferenceData),
      );
      
      print('📊 Status Code: ${response.statusCode}');
      print('📄 Response Body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        
        print('✅ Preferencia creada exitosamente');
        print('🔗 Init Point: ${data['init_point']}');
        print('🆔 Preference ID: ${data['id']}');
        
        // Retornar la URL de checkout
        return data['init_point'] as String;
      } else {
        print('❌ Error al crear preferencia');
        print('Status: ${response.statusCode}');
        print('Body: ${response.body}');
        
        // Intentar parsear el error de Mercado Pago
        try {
          final errorData = json.decode(response.body);
          if (errorData['message'] != null) {
            throw Exception('Mercado Pago: ${errorData['message']}');
          } else if (errorData['error'] != null) {
            throw Exception('Mercado Pago: ${errorData['error']}');
          } else {
            throw Exception('Error ${response.statusCode}: ${response.body}');
          }
        } catch (e) {
          if (e.toString().contains('Mercado Pago')) rethrow;
          throw Exception('Error ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      print('💥 Excepción: $e');
      rethrow;
    }
  }
  
  /// Verifica el estado de un pago
  Future<Map<String, dynamic>> getPaymentInfo(String paymentId) async {
    final url = Uri.parse('${MercadoPagoConfig.apiBaseUrl}/v1/payments/$paymentId');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${MercadoPagoConfig.accessToken}',
        },
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Error al obtener información del pago: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al verificar pago: $e');
    }
  }

  /// Busca pagos aprobados recientes para un usuario (últimos 5 minutos)
  /// Retorna true si hay un pago aprobado reciente
  Future<bool> verifyRecentPayment(String userId) async {
    try {
      print('🔍 Buscando pagos aprobados para userId: $userId');
      
      // Intentar método 1: Buscar por external_reference
      final searchResult = await _searchByExternalReference(userId);
      if (searchResult) {
        print('✅ Pago encontrado por external_reference');
        return true;
      }
      
      // Intentar método 2: Buscar todos los pagos recientes del usuario
      final recentResult = await _searchRecentPayments();
      if (recentResult) {
        print('✅ Pago encontrado en búsqueda reciente');
        return true;
      }
      
      print('⚠️ No se encontraron pagos aprobados recientes');
      return false;
    } catch (e) {
      print('💥 Excepción al verificar pago: $e');
      return false;
    }
  }
  
  Future<bool> _searchByExternalReference(String userId) async {
    try {
      final now = DateTime.now();
      final fiveMinutesAgo = now.subtract(const Duration(minutes: 5));
      
      // Formato de external_reference: SUB-userId-timestamp
      final externalRefPrefix = 'SUB-$userId';
      
      print('🔎 Método 1: Buscando por external_reference: $externalRefPrefix*');
      
      final url = Uri.parse('${MercadoPagoConfig.apiBaseUrl}/v1/payments/search');
      
      final response = await http.get(
        url.replace(queryParameters: {
          'sort': 'date_created',
          'criteria': 'desc',
          'range': 'date_created',
          'begin_date': fiveMinutesAgo.toIso8601String(),
          'end_date': now.toIso8601String(),
        }),
        headers: {
          'Authorization': 'Bearer ${MercadoPagoConfig.accessToken}',
        },
      );
      
      print('📊 Status búsqueda: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;
        
        print('📦 Pagos en rango: ${results?.length ?? 0}');
        
        if (results != null && results.isNotEmpty) {
          for (var payment in results) {
            final externalRef = payment['external_reference'] as String?;
            final status = payment['status'];
            final statusDetail = payment['status_detail'];
            final paymentId = payment['id'];
            
            print('   📝 Pago: $paymentId');
            print('      External Ref: $externalRef');
            print('      Status: $status');
            print('      Status Detail: $statusDetail');
            
            // Verificar si el external_reference contiene nuestro userId
            if (externalRef != null && 
                externalRef.startsWith(externalRefPrefix) &&
                status == 'approved') {
              print('   ✅ Pago aprobado encontrado!');
              return true;
            }
          }
        }
      } else {
        print('❌ Error en búsqueda: ${response.statusCode}');
        print('   Body: ${response.body}');
      }
      
      return false;
    } catch (e) {
      print('💥 Error en _searchByExternalReference: $e');
      return false;
    }
  }
  
  Future<bool> _searchRecentPayments() async {
    try {
      print('🔎 Método 2: Buscando pagos recientes sin filtro específico');
      
      final now = DateTime.now();
      final tenMinutesAgo = now.subtract(const Duration(minutes: 10));
      
      final url = Uri.parse('${MercadoPagoConfig.apiBaseUrl}/v1/payments/search');
      
      final response = await http.get(
        url.replace(queryParameters: {
          'status': 'approved',
          'sort': 'date_created',
          'criteria': 'desc',
          'limit': '50',
        }),
        headers: {
          'Authorization': 'Bearer ${MercadoPagoConfig.accessToken}',
        },
      );
      
      print('📊 Status búsqueda reciente: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List?;
        
        print('📦 Pagos aprobados encontrados: ${results?.length ?? 0}');
        
        if (results != null && results.isNotEmpty) {
          // Mostrar los últimos 5 pagos para debug
          final recentPayments = results.take(5);
          for (var payment in recentPayments) {
            final dateCreated = DateTime.parse(payment['date_created']);
            final externalRef = payment['external_reference'];
            final amount = payment['transaction_amount'];
            
            print('   📝 Pago ID: ${payment['id']}');
            print('      Fecha: $dateCreated');
            print('      External Ref: $externalRef');
            print('      Monto: $amount');
            print('      Minutos atrás: ${now.difference(dateCreated).inMinutes}');
            
            // Verificar si es un pago reciente de nuestra app (monto = 25000)
            if (dateCreated.isAfter(tenMinutesAgo) && 
                amount == MercadoPagoConfig.subscriptionPrice) {
              print('   ✅ Pago reciente con monto correcto encontrado!');
              return true;
            }
          }
        }
      } else {
        print('❌ Error en búsqueda reciente: ${response.statusCode}');
        print('   Body: ${response.body}');
      }
      
      return false;
    } catch (e) {
      print('💥 Error en _searchRecentPayments: $e');
      return false;
    }
  }
}
