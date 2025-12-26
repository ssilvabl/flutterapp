import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../constants/user_roles.dart';

class SessionManager {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Obtiene información del dispositivo
  static String _getDeviceInfo() {
    if (kIsWeb) {
      return 'Web Browser';
    } else if (Platform.isAndroid) {
      return 'Android Device';
    } else if (Platform.isIOS) {
      return 'iOS Device';
    } else if (Platform.isWindows) {
      return 'Windows Desktop';
    } else if (Platform.isMacOS) {
      return 'macOS Desktop';
    } else if (Platform.isLinux) {
      return 'Linux Desktop';
    }
    return 'Unknown Device';
  }

  /// Verifica si el usuario puede iniciar sesión según el límite de sesiones
  static Future<SessionCheckResult> checkSessionLimit(String userId, String userRole) async {
    try {
      // Obtener el límite de sesiones para este rol
      final UserRole role = UserRole.values.firstWhere(
        (r) => r.toString().split('.').last == userRole,
        orElse: () => UserRole.free,
      );
      final rolePermissions = RolePermissions(role);
      final int maxSessions = rolePermissions.maxActiveSessions;

      // Contar sesiones activas (últimos 7 días)
      final response = await _supabase
          .from('user_sessions')
          .select()
          .eq('user_id', userId)
          .gte('last_activity', DateTime.now().subtract(const Duration(days: 7)).toIso8601String());

      final int activeSessions = (response as List).length;

      print('SessionManager: User $userId has $activeSessions active sessions, max allowed: $maxSessions');

      if (activeSessions >= maxSessions) {
        // Obtener lista de sesiones para mostrar al usuario
        final sessions = response.map((session) => {
          'id': session['id'],
          'device_info': session['device_info'] ?? 'Dispositivo desconocido',
          'last_activity': session['last_activity'],
        }).toList();

        return SessionCheckResult(
          canLogin: false,
          activeSessions: activeSessions,
          maxSessions: maxSessions,
          sessions: sessions,
        );
      }

      return SessionCheckResult(
        canLogin: true,
        activeSessions: activeSessions,
        maxSessions: maxSessions,
        sessions: [],
      );
    } catch (e) {
      print('Error checking session limit: $e');
      // En caso de error, permitir el inicio de sesión
      return SessionCheckResult(canLogin: true, activeSessions: 0, maxSessions: 999, sessions: []);
    }
  }

  /// Crea una nueva sesión para el usuario actual
  static Future<void> createSession() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        print('No user logged in');
        return;
      }

      final sessionToken = _supabase.auth.currentSession?.accessToken ?? '';
      final deviceInfo = _getDeviceInfo();

      await _supabase.from('user_sessions').insert({
        'user_id': userId,
        'session_token': sessionToken,
        'device_info': deviceInfo,
        'last_activity': DateTime.now().toIso8601String(),
      });

      print('SessionManager: Session created for user $userId on $deviceInfo');
    } catch (e) {
      print('Error creating session: $e');
    }
  }

  /// Actualiza la actividad de la sesión actual
  static Future<void> updateSessionActivity() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      final sessionToken = _supabase.auth.currentSession?.accessToken;

      if (userId == null || sessionToken == null) {
        return;
      }

      await _supabase
          .from('user_sessions')
          .update({'last_activity': DateTime.now().toIso8601String()})
          .eq('user_id', userId)
          .eq('session_token', sessionToken);

      print('SessionManager: Session activity updated');
    } catch (e) {
      print('Error updating session activity: $e');
    }
  }

  /// Elimina sesiones específicas
  static Future<void> removeSessions(List<String> sessionIds) async {
    try {
      await _supabase.from('user_sessions').delete().in_('id', sessionIds);
      print('SessionManager: Removed ${sessionIds.length} sessions');
    } catch (e) {
      print('Error removing sessions: $e');
      rethrow;
    }
  }

  /// Elimina la sesión actual al cerrar sesión
  static Future<void> removeCurrentSession() async {
    try {
      final sessionToken = _supabase.auth.currentSession?.accessToken;
      if (sessionToken != null) {
        await _supabase
            .from('user_sessions')
            .delete()
            .eq('session_token', sessionToken);
        print('SessionManager: Current session removed');
      }
    } catch (e) {
      print('Error removing current session: $e');
    }
  }

  /// Obtiene el conteo de transacciones del usuario
  static Future<int> getTransactionCount(String userId) async {
    try {
      final response = await _supabase
          .from('payments')
          .select('id', const FetchOptions(count: CountOption.exact))
          .eq('user_id', userId);

      return response.count ?? 0;
    } catch (e) {
      print('Error getting transaction count: $e');
      return 0;
    }
  }

  /// Verifica si el usuario puede agregar más transacciones
  static Future<TransactionLimitResult> checkTransactionLimit(String userId, String userRole) async {
    try {
      final UserRole role = UserRole.values.firstWhere(
        (r) => r.toString().split('.').last == userRole,
        orElse: () => UserRole.free,
      );

      final rolePermissions = RolePermissions(role);
      final int? maxTransactions = rolePermissions.maxTransactions;
      
      // Admin tiene transacciones ilimitadas
      if (maxTransactions == null) {
        return TransactionLimitResult(
          canAdd: true,
          currentCount: 0,
          maxCount: null,
        );
      }

      final int currentCount = await getTransactionCount(userId);

      return TransactionLimitResult(
        canAdd: currentCount < maxTransactions,
        currentCount: currentCount,
        maxCount: maxTransactions,
      );
    } catch (e) {
      print('Error checking transaction limit: $e');
      // En caso de error, permitir agregar
      return TransactionLimitResult(canAdd: true, currentCount: 0, maxCount: null);
    }
  }
}

/// Resultado de la verificación de sesiones
class SessionCheckResult {
  final bool canLogin;
  final int activeSessions;
  final int maxSessions;
  final List<Map<String, dynamic>> sessions;

  SessionCheckResult({
    required this.canLogin,
    required this.activeSessions,
    required this.maxSessions,
    required this.sessions,
  });
}

/// Resultado de la verificación de límite de transacciones
class TransactionLimitResult {
  final bool canAdd;
  final int currentCount;
  final int? maxCount;

  TransactionLimitResult({
    required this.canAdd,
    required this.currentCount,
    this.maxCount,
  });

  String get message {
    if (maxCount == null) {
      return 'Transacciones ilimitadas';
    }
    return '$currentCount / $maxCount transacciones';
  }
}
