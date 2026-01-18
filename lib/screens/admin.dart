import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../constants/user_roles.dart';
import '../utils/error_messages.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class UserInfo {
  final String id;
  final String email;
  final String? fullName;
  final String? company;
  final String role;
  final DateTime createdAt;
  final int totalPayments;
  final int totalCollections;
  final int activeSessions;

  UserInfo({
    required this.id,
    required this.email,
    this.fullName,
    this.company,
    required this.role,
    required this.createdAt,
    required this.totalPayments,
    required this.totalCollections,
    required this.activeSessions,
  });
}

class _AdminPageState extends State<AdminPage> {
  final _supabase = Supabase.instance.client;
  List<UserInfo> _users = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      // Obtener todos los perfiles
      final profilesRes = await _supabase
          .from('profiles')
          .select()
          .order('updated_at', ascending: false);

      final profiles = List<Map<String, dynamic>>.from(profilesRes);

      // Para cada perfil, obtener su email y contar pagos/cobros
      final List<UserInfo> usersList = [];
      for (final profile in profiles) {
        final userId = profile['id'] as String;

        // Obtener email del usuario
        String email = 'N/A';
        try {
          email = profile['email'] as String? ?? userId;
        } catch (_) {}

        // Contar pagos y cobros
        final paymentsRes = await _supabase
            .from('payments')
            .select('type')
            .eq('user_id', userId);

        final payments = List<Map<String, dynamic>>.from(paymentsRes);
        final totalPayments = payments.where((p) => p['type'] == 'pago').length;
        final totalCollections =
            payments.where((p) => p['type'] == 'cobro').length;

        // Contar sesiones activas
        final sessionsRes = await _supabase
            .from('user_sessions')
            .select('id')
            .eq('user_id', userId);
        final activeSessions = (sessionsRes as List).length;

        usersList.add(UserInfo(
          id: userId,
          email: email,
          fullName: profile['full_name'] as String?,
          company: profile['company'] as String?,
          role: profile['role'] as String? ?? 'free',
          createdAt: profile['updated_at'] != null
              ? DateTime.parse(profile['updated_at'] as String)
              : DateTime.now(),
          totalPayments: totalPayments,
          totalCollections: totalCollections,
          activeSessions: activeSessions,
        ));
      }

      setState(() {
        _users = usersList;
      });
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'Error al cargar usuarios');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendRecoveryEmail(UserInfo user) async {
    try {
      // Mostrar diálogo de confirmación
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reenviar correo de recuperación'),
          content: Text(
              '¿Enviar correo de recuperación a ${user.email}?\n\nEl usuario recibirá un enlace para restablecer su contraseña.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // Enviar email de recuperación
      await _supabase.auth.resetPasswordForEmail(user.email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Correo de recuperación enviado exitosamente')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e,
          fallback: 'Error al enviar correo de recuperación');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _changeUserRole(UserInfo user) async {
    final currentRole = UserRoleExtension.fromString(user.role);
    UserRole? selectedRole = currentRole;
    int? selectedMonths;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => AlertDialog(
          title: Text('Cambiar rol de ${user.fullName ?? user.email}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<UserRole>(
                title: const Text('Admin'),
                subtitle: const Text('Acceso completo al sistema'),
                value: UserRole.admin,
                groupValue: selectedRole,
                onChanged: (value) {
                  setStateDialog(() {
                    selectedRole = value;
                    selectedMonths = null;
                  });
                },
              ),
              RadioListTile<UserRole>(
                title: const Text('Premium'),
                subtitle: const Text('Funciones premium'),
                value: UserRole.premium,
                groupValue: selectedRole,
                onChanged: (value) {
                  setStateDialog(() => selectedRole = value);
                },
              ),
              RadioListTile<UserRole>(
                title: const Text('Free'),
                subtitle: const Text('Acceso básico'),
                value: UserRole.free,
                groupValue: selectedRole,
                onChanged: (value) {
                  setStateDialog(() {
                    selectedRole = value;
                    selectedMonths = null;
                  });
                },
              ),

              // Mostrar selector de meses si es Premium (actual o nuevo)
              if (selectedRole == UserRole.premium ||
                  (currentRole == UserRole.premium &&
                      selectedRole == UserRole.premium))
                Column(
                  children: [
                    const Divider(height: 32),
                    const Text(
                      'Agregar tiempo Premium:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('1 mes'),
                          selected: selectedMonths == 1,
                          onSelected: (selected) {
                            setStateDialog(
                                () => selectedMonths = selected ? 1 : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('2 meses'),
                          selected: selectedMonths == 2,
                          onSelected: (selected) {
                            setStateDialog(
                                () => selectedMonths = selected ? 2 : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('3 meses'),
                          selected: selectedMonths == 3,
                          onSelected: (selected) {
                            setStateDialog(
                                () => selectedMonths = selected ? 3 : null);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop({
                'role': selectedRole,
                'months': selectedMonths,
              }),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    final newRole = result['role'] as UserRole?;
    final months = result['months'] as int?;

    if (newRole == null || (newRole == currentRole && months == null)) return;

    try {
      final updates = <String, dynamic>{'role': newRole.value};

      // Si se seleccionó Premium y hay meses, calcular fechas
      if (newRole == UserRole.premium && months != null) {
        final now = DateTime.now();

        // Si ya es premium, extender desde subscription_end, sino desde ahora
        DateTime startDate = now;
        if (currentRole == UserRole.premium) {
          // Obtener la fecha de fin actual
          final profile = await _supabase
              .from('profiles')
              .select('subscription_end')
              .eq('id', user.id)
              .single();

          if (profile['subscription_end'] != null) {
            final currentEnd = DateTime.parse(profile['subscription_end']);
            startDate = currentEnd.isAfter(now) ? currentEnd : now;
          }
        }

        final endDate = DateTime(
          startDate.year,
          startDate.month + months,
          startDate.day,
        );

        updates['subscription_start'] = currentRole == UserRole.premium
            ? null // Mantener la fecha de inicio original
            : now.toIso8601String();
        updates['subscription_end'] = endDate.toIso8601String();
        updates['subscription_cancelled'] = false;
      }

      await _supabase.from('profiles').update(updates).eq('id', user.id);

      if (!mounted) return;

      String message = 'Rol actualizado exitosamente';
      if (months != null) {
        message +=
            '\n+$months ${months == 1 ? 'mes' : 'meses'} Premium agregado${months > 1 ? 's' : ''}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );

      // Recargar usuarios
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'Error al actualizar rol');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _closeAllSessions(UserInfo user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar todas las sesiones'),
        content: Text(
            '¿Cerrar todas las sesiones activas de ${user.fullName ?? user.email}?\n\nEl usuario será desconectado de todos sus dispositivos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar todas'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _supabase.from('user_sessions').delete().eq('user_id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesiones cerradas exitosamente')),
      );

      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'Error al cerrar sesiones');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _showSessionsDialog(UserInfo user) async {
    if (user.activeSessions == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El usuario no tiene sesiones activas')),
      );
      return;
    }

    // Obtener todas las sesiones del usuario
    final sessionsRes = await _supabase
        .from('user_sessions')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final sessions = List<Map<String, dynamic>>.from(sessionsRes);

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sesiones de ${user.fullName ?? user.email}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final device = session['device_info'] as String? ??
                  'Dispositivo desconocido';
              final createdAt = session['created_at'] != null
                  ? DateTime.parse(session['created_at'] as String)
                  : null;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.devices),
                  title: Text(device),
                  subtitle: createdAt != null
                      ? Text(
                          'Iniciada: ${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}')
                      : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () async {
                      try {
                        await _supabase
                            .from('user_sessions')
                            .delete()
                            .eq('id', session['id']);

                        if (!mounted) return;
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Sesión cerrada exitosamente')),
                        );
                        await _loadUsers();
                      } catch (e) {
                        if (!mounted) return;
                        final msg = friendlySupabaseMessage(e,
                            fallback: 'Error al cerrar sesión');
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(msg)));
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ============ BACKUP FUNCTIONS ============

  Future<void> _downloadUserBackup(UserInfo user) async {
    try {
      setState(() => _loading = true);

      // Obtener todos los datos del usuario
      final profile =
          await _supabase.from('profiles').select().eq('id', user.id).single();

      final payments =
          await _supabase.from('payments').select().eq('user_id', user.id);

      // Obtener todos los movimientos de los pagos del usuario
      final paymentIds = (payments as List).map((p) => p['id']).toList();
      List<dynamic> movements = [];
      if (paymentIds.isNotEmpty) {
        movements = await _supabase
            .from('payments_movements')
            .select()
            .in_('payment_id', paymentIds);
      }

      final sessions =
          await _supabase.from('user_sessions').select().eq('user_id', user.id);

      // Generar SQL
      final sql = StringBuffer();
      sql.writeln('-- Backup de datos del usuario: ${user.email}');
      sql.writeln('-- Fecha: ${DateTime.now().toIso8601String()}');
      sql.writeln('-- ID Usuario: ${user.id}');
      sql.writeln();

      // Profile
      sql.writeln('-- ============ PROFILE ============');
      sql.writeln(
          'INSERT INTO profiles (id, email, full_name, company, role, subscription_start, subscription_end, subscription_cancelled, interface_preference, updated_at, created_at)');
      sql.writeln('VALUES (');
      sql.writeln("  '${profile['id']}',");
      sql.writeln("  ${_sqlValue(profile['email'])},");
      sql.writeln("  ${_sqlValue(profile['full_name'])},");
      sql.writeln("  ${_sqlValue(profile['company'])},");
      sql.writeln("  ${_sqlValue(profile['role'])},");
      sql.writeln("  ${_sqlValue(profile['subscription_start'])},");
      sql.writeln("  ${_sqlValue(profile['subscription_end'])},");
      sql.writeln("  ${profile['subscription_cancelled'] ?? false},");
      sql.writeln("  ${_sqlValue(profile['interface_preference'])},");
      sql.writeln("  ${_sqlValue(profile['updated_at'])},");
      sql.writeln("  ${_sqlValue(profile['created_at'])}");
      sql.writeln(');');
      sql.writeln();

      // Payments
      if (payments.isNotEmpty) {
        sql.writeln('-- ============ PAYMENTS ============');
        for (final payment in payments) {
          sql.writeln(
              'INSERT INTO payments (id, user_id, entity, amount, type, description, created_at, end_date)');
          sql.writeln('VALUES (');
          sql.writeln("  ${payment['id']},");
          sql.writeln("  '${payment['user_id']}',");
          sql.writeln("  ${_sqlValue(payment['entity'])},");
          sql.writeln("  ${payment['amount']},");
          sql.writeln("  ${_sqlValue(payment['type'])},");
          sql.writeln("  ${_sqlValue(payment['description'])},");
          sql.writeln("  ${_sqlValue(payment['created_at'])},");
          sql.writeln("  ${_sqlValue(payment['end_date'])}");
          sql.writeln(');');
        }
        sql.writeln();
      }

      // Movements
      if (movements.isNotEmpty) {
        sql.writeln('-- ============ PAYMENT MOVEMENTS ============');
        for (final movement in movements) {
          sql.writeln(
              'INSERT INTO payments_movements (id, payment_id, amount, movement_type, created_at)');
          sql.writeln('VALUES (');
          sql.writeln("  ${movement['id']},");
          sql.writeln("  ${movement['payment_id']},");
          sql.writeln("  ${movement['amount']},");
          sql.writeln("  ${_sqlValue(movement['movement_type'])},");
          sql.writeln("  ${_sqlValue(movement['created_at'])}");
          sql.writeln(');');
        }
        sql.writeln();
      }

      // Sessions
      if (sessions.isNotEmpty) {
        sql.writeln('-- ============ USER SESSIONS ============');
        for (final session in sessions as List) {
          sql.writeln(
              'INSERT INTO user_sessions (id, user_id, device_info, created_at)');
          sql.writeln('VALUES (');
          sql.writeln("  '${session['id']}',");
          sql.writeln("  '${session['user_id']}',");
          sql.writeln("  ${_sqlValue(session['device_info'])},");
          sql.writeln("  ${_sqlValue(session['created_at'])}");
          sql.writeln(');');
        }
        sql.writeln();
      }

      // Guardar archivo
      await _saveAndShareFile(sql.toString(),
          'backup_user_${user.id}_${DateTime.now().millisecondsSinceEpoch}.sql');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Backup del usuario generado exitosamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar backup: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadFullBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Backup completo'),
        content: const Text(
            '¿Desea generar un backup completo de la base de datos?\n\n'
            'Esto incluye:\n'
            '• Estructura completa de TODAS las tablas\n'
            '• Todos los usuarios y perfiles\n'
            '• Todos los pagos y movimientos\n'
            '• Todas las sesiones activas\n'
            '• Todas las suscripciones y pagos de Mercado Pago\n'
            '• Políticas RLS e índices\n\n'
            'Este proceso puede tardar varios minutos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Generar backup'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Mostrar diálogo de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
                'Generando backup completo...\nEsto puede tardar varios minutos.'),
          ],
        ),
      ),
    );

    try {
      setState(() => _loading = true);

      // Obtener TODOS los datos de TODAS las tablas usando funciones RPC administrativas
      // Estas funciones bypasean RLS usando SECURITY DEFINER
      List<dynamic> profiles = [];
      List<dynamic> payments = [];
      List<dynamic> movements = [];
      List<dynamic> sessions = [];
      List<dynamic> mercadopagoPayments = [];
      List<dynamic> subscriptions = [];

      try {
        // Usar funciones RPC administrativas que bypasean RLS
        profiles = await _supabase.rpc('get_all_profiles_admin') as List;
        payments = await _supabase.rpc('get_all_payments_admin') as List;
        movements = await _supabase.rpc('get_all_movements_admin') as List;
        sessions = await _supabase.rpc('get_all_sessions_admin') as List;

        try {
          mercadopagoPayments =
              await _supabase.rpc('get_all_mercadopago_payments_admin') as List;
        } catch (_) {
          // Tabla puede no existir
        }

        try {
          subscriptions =
              await _supabase.rpc('get_all_subscriptions_admin') as List;
        } catch (_) {
          // Tabla puede no existir
        }
      } catch (e) {
        // Cerrar diálogo de progreso si está abierto
        if (mounted) Navigator.pop(context);

        print('Error obteniendo datos: $e');
        throw Exception('Error al obtener datos para backup.\n\n'
            'Asegúrate de:\n'
            '1. Tener rol de administrador\n'
            '2. Haber ejecutado el script SQL:\n'
            '   db/migrations/20260113_add_admin_backup_functions.sql\n\n'
            'Error: $e');
      }

      final sql = StringBuffer();
      sql.writeln('-- ============================================');
      sql.writeln('-- BACKUP COMPLETO - SEPAGOS APP');
      sql.writeln('-- Fecha: ${DateTime.now().toIso8601String()}');
      sql.writeln('-- Generado desde: Admin Panel');
      sql.writeln('-- ============================================');
      sql.writeln();

      sql.writeln(
          '-- Desactivar verificaciones temporalmente para importación');
      sql.writeln('SET session_replication_role = replica;');
      sql.writeln();

      // ============ ESTRUCTURA DE TABLAS ============
      sql.writeln('-- ============================================');
      sql.writeln('-- ESTRUCTURA DE TABLAS');
      sql.writeln('-- ============================================');
      sql.writeln();

      // Profiles table
      sql.writeln('-- Tabla: profiles');
      sql.writeln('DROP TABLE IF EXISTS profiles CASCADE;');
      sql.writeln('CREATE TABLE profiles (');
      sql.writeln('  id UUID PRIMARY KEY,');
      sql.writeln('  email TEXT,');
      sql.writeln('  full_name TEXT,');
      sql.writeln('  company TEXT,');
      sql.writeln('  role TEXT DEFAULT \'free\',');
      sql.writeln('  subscription_start TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  subscription_end TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  subscription_cancelled BOOLEAN DEFAULT false,');
      sql.writeln('  interface_preference TEXT DEFAULT \'prestamista\',');
      sql.writeln('  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()');
      sql.writeln(');');
      sql.writeln();

      // Payments table
      sql.writeln('-- Tabla: payments');
      sql.writeln('DROP TABLE IF EXISTS payments CASCADE;');
      sql.writeln('CREATE TABLE payments (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  user_id UUID NOT NULL,');
      sql.writeln('  entity_name TEXT NOT NULL,');
      sql.writeln('  amount NUMERIC(15,2) NOT NULL DEFAULT 0,');
      sql.writeln(
          '  type TEXT NOT NULL CHECK (type IN (\'cobro\', \'pago\')),');
      sql.writeln('  description TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln('  end_date TIMESTAMP WITH TIME ZONE,');
      sql.writeln(
          '  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE');
      sql.writeln(');');
      sql.writeln();

      // Payments movements table
      sql.writeln('-- Tabla: payments_movements');
      sql.writeln('DROP TABLE IF EXISTS payments_movements CASCADE;');
      sql.writeln('CREATE TABLE payments_movements (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  payment_id BIGINT NOT NULL,');
      sql.writeln('  user_id UUID,');
      sql.writeln('  amount NUMERIC(15,2) NOT NULL,');
      sql.writeln(
          '  movement_type TEXT NOT NULL CHECK (movement_type IN (\'initial\', \'increment\', \'reduction\')),');
      sql.writeln('  note TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln(
          '  FOREIGN KEY (payment_id) REFERENCES payments(id) ON DELETE CASCADE');
      sql.writeln(');');
      sql.writeln();

      // User sessions table
      sql.writeln('-- Tabla: user_sessions');
      sql.writeln('DROP TABLE IF EXISTS user_sessions CASCADE;');
      sql.writeln('CREATE TABLE user_sessions (');
      sql.writeln('  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),');
      sql.writeln('  user_id UUID NOT NULL,');
      sql.writeln('  device_info TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln(
          '  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE');
      sql.writeln(');');
      sql.writeln();

      // MercadoPago payments table
      sql.writeln('-- Tabla: mercadopago_payments');
      sql.writeln('DROP TABLE IF EXISTS mercadopago_payments CASCADE;');
      sql.writeln('CREATE TABLE mercadopago_payments (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  user_id UUID NOT NULL,');
      sql.writeln('  payment_id TEXT UNIQUE,');
      sql.writeln('  preference_id TEXT,');
      sql.writeln('  status TEXT,');
      sql.writeln('  amount NUMERIC(15,2),');
      sql.writeln('  payment_method TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln('  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln(
          '  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE');
      sql.writeln(');');
      sql.writeln();

      // Subscriptions table
      sql.writeln('-- Tabla: subscriptions');
      sql.writeln('DROP TABLE IF EXISTS subscriptions CASCADE;');
      sql.writeln('CREATE TABLE subscriptions (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  user_id UUID NOT NULL UNIQUE,');
      sql.writeln('  plan TEXT NOT NULL,');
      sql.writeln('  status TEXT NOT NULL,');
      sql.writeln('  start_date TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  end_date TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  auto_renew BOOLEAN DEFAULT true,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln('  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln(
          '  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE');
      sql.writeln(');');
      sql.writeln();

      // ============ ÍNDICES ============
      sql.writeln('-- ============================================');
      sql.writeln('-- ÍNDICES');
      sql.writeln('-- ============================================');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_payments_user_id ON payments(user_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_payments_type ON payments(type);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at DESC);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_movements_payment_id ON payments_movements(payment_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_movements_user_id ON payments_movements(user_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON user_sessions(user_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_mp_payments_user_id ON mercadopago_payments(user_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_mp_payments_payment_id ON mercadopago_payments(payment_id);');
      sql.writeln(
          'CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions(user_id);');
      sql.writeln();

      // ============ ROW LEVEL SECURITY ============
      sql.writeln('-- ============================================');
      sql.writeln('-- ROW LEVEL SECURITY (RLS)');
      sql.writeln('-- ============================================');
      sql.writeln('ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE payments ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE payments_movements ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;');
      sql.writeln(
          'ALTER TABLE mercadopago_payments ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;');
      sql.writeln();

      sql.writeln('-- Políticas para profiles');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can view own profile" ON profiles;');
      sql.writeln(
          'CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can update own profile" ON profiles;');
      sql.writeln(
          'CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);');
      sql.writeln();

      sql.writeln('-- Políticas para payments');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can view own payments" ON payments;');
      sql.writeln(
          'CREATE POLICY "Users can view own payments" ON payments FOR SELECT USING (auth.uid() = user_id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can insert own payments" ON payments;');
      sql.writeln(
          'CREATE POLICY "Users can insert own payments" ON payments FOR INSERT WITH CHECK (auth.uid() = user_id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can update own payments" ON payments;');
      sql.writeln(
          'CREATE POLICY "Users can update own payments" ON payments FOR UPDATE USING (auth.uid() = user_id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can delete own payments" ON payments;');
      sql.writeln(
          'CREATE POLICY "Users can delete own payments" ON payments FOR DELETE USING (auth.uid() = user_id);');
      sql.writeln();

      sql.writeln('-- Políticas para payments_movements');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can view movements of own payments" ON payments_movements;');
      sql.writeln(
          'CREATE POLICY "Users can view movements of own payments" ON payments_movements FOR SELECT');
      sql.writeln(
          '  USING (EXISTS (SELECT 1 FROM payments WHERE payments.id = payments_movements.payment_id AND payments.user_id = auth.uid()));');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can insert movements to own payments" ON payments_movements;');
      sql.writeln(
          'CREATE POLICY "Users can insert movements to own payments" ON payments_movements FOR INSERT');
      sql.writeln(
          '  WITH CHECK (EXISTS (SELECT 1 FROM payments WHERE payments.id = payments_movements.payment_id AND payments.user_id = auth.uid()));');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can delete movements of own payments" ON payments_movements;');
      sql.writeln(
          'CREATE POLICY "Users can delete movements of own payments" ON payments_movements FOR DELETE');
      sql.writeln(
          '  USING (EXISTS (SELECT 1 FROM payments WHERE payments.id = payments_movements.payment_id AND payments.user_id = auth.uid()));');
      sql.writeln();

      sql.writeln('-- Políticas para user_sessions');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can view own sessions" ON user_sessions;');
      sql.writeln(
          'CREATE POLICY "Users can view own sessions" ON user_sessions FOR SELECT USING (auth.uid() = user_id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can insert own sessions" ON user_sessions;');
      sql.writeln(
          'CREATE POLICY "Users can insert own sessions" ON user_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);');
      sql.writeln(
          'DROP POLICY IF EXISTS "Users can delete own sessions" ON user_sessions;');
      sql.writeln(
          'CREATE POLICY "Users can delete own sessions" ON user_sessions FOR DELETE USING (auth.uid() = user_id);');
      sql.writeln();

      // ============ DATOS ============
      sql.writeln('-- ============================================');
      sql.writeln('-- DATOS');
      sql.writeln('-- ============================================');
      sql.writeln();

      // Profiles
      if (profiles.isNotEmpty) {
        sql.writeln('-- Insertando ${(profiles).length} perfiles');
        for (final profile in profiles) {
          sql.write(
              'INSERT INTO profiles (id, email, full_name, company, role, subscription_start, subscription_end, subscription_cancelled, interface_preference, updated_at) VALUES (');
          sql.write("'${profile['id']}', ");
          sql.write("${_sqlValue(profile['email'])}, ");
          sql.write("${_sqlValue(profile['full_name'])}, ");
          sql.write("${_sqlValue(profile['company'])}, ");
          sql.write("${_sqlValue(profile['role'])}, ");
          sql.write("${_sqlValue(profile['subscription_start'])}, ");
          sql.write("${_sqlValue(profile['subscription_end'])}, ");
          sql.write("${profile['subscription_cancelled'] ?? false}, ");
          sql.write("${_sqlValue(profile['interface_preference'])}, ");
          sql.write(_sqlValue(profile['updated_at']));
          sql.writeln(
              ') ON CONFLICT (id) DO UPDATE SET email=EXCLUDED.email, full_name=EXCLUDED.full_name, company=EXCLUDED.company, role=EXCLUDED.role, subscription_start=EXCLUDED.subscription_start, subscription_end=EXCLUDED.subscription_end, subscription_cancelled=EXCLUDED.subscription_cancelled, interface_preference=EXCLUDED.interface_preference, updated_at=EXCLUDED.updated_at;');
        }
        sql.writeln();
      }

      // Payments
      if (payments.isNotEmpty) {
        sql.writeln('-- Insertando ${(payments).length} pagos');
        sql.writeln(
            'SELECT setval(pg_get_serial_sequence(\'payments\', \'id\'), (SELECT MAX(id) FROM payments));');
        for (final payment in payments) {
          sql.write(
              'INSERT INTO payments (id, user_id, entity_name, amount, type, description, created_at, end_date) VALUES (');
          sql.write("${payment['id']}, ");
          sql.write("'${payment['user_id']}', ");
          sql.write("${_sqlValue(payment['entity_name'])}, ");
          sql.write("${payment['amount']}, ");
          sql.write("${_sqlValue(payment['type'])}, ");
          sql.write("${_sqlValue(payment['description'])}, ");
          sql.write("${_sqlValue(payment['created_at'])}, ");
          sql.write(_sqlValue(payment['end_date']));
          sql.writeln(
              ') ON CONFLICT (id) DO UPDATE SET entity_name=EXCLUDED.entity_name, amount=EXCLUDED.amount, type=EXCLUDED.type, description=EXCLUDED.description, end_date=EXCLUDED.end_date;');
        }
        sql.writeln();
      }

      // Movements
      if (movements.isNotEmpty) {
        sql.writeln('-- Insertando ${(movements).length} movimientos');
        sql.writeln(
            'SELECT setval(pg_get_serial_sequence(\'payments_movements\', \'id\'), (SELECT MAX(id) FROM payments_movements));');
        for (final movement in movements) {
          sql.write(
              'INSERT INTO payments_movements (id, payment_id, user_id, amount, movement_type, note, created_at) VALUES (');
          sql.write("${movement['id']}, ");
          sql.write("${movement['payment_id']}, ");
          sql.write("${_sqlValue(movement['user_id'])}, ");
          sql.write("${movement['amount']}, ");
          sql.write("${_sqlValue(movement['movement_type'])}, ");
          sql.write("${_sqlValue(movement['note'])}, ");
          sql.write(_sqlValue(movement['created_at']));
          sql.writeln(
              ') ON CONFLICT (id) DO UPDATE SET amount=EXCLUDED.amount, movement_type=EXCLUDED.movement_type, note=EXCLUDED.note;');
        }
        sql.writeln();
      }

      // Sessions
      if (sessions.isNotEmpty) {
        sql.writeln('-- Insertando ${(sessions).length} sesiones');
        for (final session in sessions) {
          sql.write(
              'INSERT INTO user_sessions (id, user_id, device_info, created_at) VALUES (');
          sql.write("'${session['id']}', ");
          sql.write("'${session['user_id']}', ");
          sql.write("${_sqlValue(session['device_info'])}, ");
          sql.write(_sqlValue(session['created_at']));
          sql.writeln(') ON CONFLICT (id) DO NOTHING;');
        }
        sql.writeln();
      }

      // MercadoPago payments
      if (mercadopagoPayments.isNotEmpty) {
        sql.writeln(
            '-- Insertando ${mercadopagoPayments.length} pagos de MercadoPago');
        for (final mp in mercadopagoPayments) {
          sql.write(
              'INSERT INTO mercadopago_payments (id, user_id, payment_id, preference_id, status, amount, payment_method, created_at, updated_at) VALUES (');
          sql.write("${mp['id']}, ");
          sql.write("'${mp['user_id']}', ");
          sql.write("${_sqlValue(mp['payment_id'])}, ");
          sql.write("${_sqlValue(mp['preference_id'])}, ");
          sql.write("${_sqlValue(mp['status'])}, ");
          sql.write("${mp['amount']}, ");
          sql.write("${_sqlValue(mp['payment_method'])}, ");
          sql.write("${_sqlValue(mp['created_at'])}, ");
          sql.write(_sqlValue(mp['updated_at']));
          sql.writeln(
              ') ON CONFLICT (id) DO UPDATE SET status=EXCLUDED.status, amount=EXCLUDED.amount, updated_at=EXCLUDED.updated_at;');
        }
        sql.writeln();
      }

      // Subscriptions
      if (subscriptions.isNotEmpty) {
        sql.writeln('-- Insertando ${subscriptions.length} suscripciones');
        for (final sub in subscriptions) {
          sql.write(
              'INSERT INTO subscriptions (id, user_id, plan, status, start_date, end_date, auto_renew, created_at, updated_at) VALUES (');
          sql.write("${sub['id']}, ");
          sql.write("'${sub['user_id']}', ");
          sql.write("${_sqlValue(sub['plan'])}, ");
          sql.write("${_sqlValue(sub['status'])}, ");
          sql.write("${_sqlValue(sub['start_date'])}, ");
          sql.write("${_sqlValue(sub['end_date'])}, ");
          sql.write("${sub['auto_renew'] ?? true}, ");
          sql.write("${_sqlValue(sub['created_at'])}, ");
          sql.write(_sqlValue(sub['updated_at']));
          sql.writeln(
              ') ON CONFLICT (user_id) DO UPDATE SET plan=EXCLUDED.plan, status=EXCLUDED.status, start_date=EXCLUDED.start_date, end_date=EXCLUDED.end_date, auto_renew=EXCLUDED.auto_renew, updated_at=EXCLUDED.updated_at;');
        }
        sql.writeln();
      }

      sql.writeln('-- Reactivar verificaciones');
      sql.writeln('SET session_replication_role = DEFAULT;');
      sql.writeln();

      sql.writeln('-- ============================================');
      sql.writeln('-- RESUMEN DEL BACKUP');
      sql.writeln('-- ============================================');
      sql.writeln(
          '-- Fecha de generación: ${DateTime.now().toIso8601String()}');
      sql.writeln('-- Total de tablas: 6');
      sql.writeln('-- Total perfiles: ${(profiles).length}');
      sql.writeln('-- Total pagos/cobros: ${(payments).length}');
      sql.writeln('-- Total movimientos: ${(movements).length}');
      sql.writeln('-- Total sesiones activas: ${(sessions).length}');
      sql.writeln('-- Total pagos MercadoPago: ${mercadopagoPayments.length}');
      sql.writeln('-- Total suscripciones: ${subscriptions.length}');

      int totalRecords = (profiles).length +
          (payments).length +
          (movements).length +
          (sessions).length +
          mercadopagoPayments.length +
          subscriptions.length;

      sql.writeln('-- TOTAL REGISTROS: $totalRecords');
      sql.writeln('-- ============================================');
      sql.writeln('-- BACKUP COMPLETADO EXITOSAMENTE');
      sql.writeln('-- ============================================');

      // Guardar archivo
      final filename =
          'backup_completo_sepagos_${DateTime.now().millisecondsSinceEpoch}.sql';
      await _saveAndShareFile(sql.toString(), filename);

      // Cerrar diálogo de progreso
      if (mounted) Navigator.pop(context);

      // Mostrar diálogo de resumen
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 32),
              SizedBox(width: 12),
              Text('Backup Completado'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El backup se ha generado exitosamente.',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('📊 RESUMEN DEL BACKUP:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildSummaryRow('Tablas exportadas', '6'),
                _buildSummaryRow('Perfiles/Usuarios', '${(profiles).length}'),
                _buildSummaryRow('Pagos y Cobros', '${(payments).length}'),
                _buildSummaryRow('Movimientos', '${(movements).length}'),
                _buildSummaryRow('Sesiones activas', '${(sessions).length}'),
                _buildSummaryRow(
                    'Pagos MercadoPago', '${mercadopagoPayments.length}'),
                _buildSummaryRow('Suscripciones', '${subscriptions.length}'),
                const Divider(),
                _buildSummaryRow('TOTAL REGISTROS', '$totalRecords',
                    bold: true),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.info_outline,
                              size: 18, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('Incluye:',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('✓ Estructura completa de tablas'),
                      const Text('✓ Todos los datos e información'),
                      const Text('✓ Índices y constraints'),
                      const Text('✓ Políticas RLS configuradas'),
                      const SizedBox(height: 8),
                      Text(
                        'Archivo: $filename',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.check),
              label: const Text('Entendido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      // Cerrar diálogo de progreso si está abierto
      if (mounted) Navigator.pop(context);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al generar backup completo: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildSummaryRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 15 : 14,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 14,
              fontWeight: FontWeight.bold,
              color: bold ? Colors.blue : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _sqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is String) {
      // Escapar comillas simples
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (value is bool) return value ? 'true' : 'false';
    return value.toString();
  }

  Future<void> _saveAndShareFile(String content, String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');
      await file.writeAsString(content);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Backup SQL - Sepagos',
      );
    } catch (e) {
      throw Exception('Error al guardar archivo: $e');
    }
  }

  void _showActionsMenu(UserInfo user) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.email),
              title: const Text('Reenviar correo de recuperación'),
              onTap: () {
                Navigator.of(ctx).pop();
                _resendRecoveryEmail(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Cambiar rol'),
              onTap: () {
                Navigator.of(ctx).pop();
                _changeUserRole(user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: Colors.blue),
              title: const Text('Descargar base de datos del usuario en SQL'),
              onTap: () {
                Navigator.of(ctx).pop();
                _downloadUserBackup(user);
              },
            ),
            if (user.activeSessions > 0) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.devices_other),
                title: const Text('Ver sesiones por dispositivo'),
                subtitle: Text('${user.activeSessions} sesión(es) activa(s)'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showSessionsDialog(user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Cerrar todas las sesiones'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _closeAllSessions(user);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        backgroundColor: const Color(0xFF1F2323),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Descargar backup completo',
            onPressed: _downloadFullBackup,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: _users.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 80),
                        Center(child: Text('No hay usuarios registrados')),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Usuarios Registrados',
                          style: TextStyle(
                              fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Usuario')),
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('Rol')),
                                DataColumn(label: Text('Registro')),
                                DataColumn(label: Text('Pagos')),
                                DataColumn(label: Text('Cobros')),
                                DataColumn(label: Text('Sesiones')),
                                DataColumn(label: Text('Acciones')),
                              ],
                              rows: _users.map((user) {
                                final roleColor = user.role == 'admin'
                                    ? Colors.red
                                    : user.role == 'premium'
                                        ? Colors.amber
                                        : Colors.grey;

                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            user.fullName ?? 'Sin nombre',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold),
                                          ),
                                          if (user.company != null)
                                            Text(
                                              user.company!,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey),
                                            ),
                                        ],
                                      ),
                                    ),
                                    DataCell(Text(user.email)),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: roleColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          user.role.toUpperCase(),
                                          style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          const Icon(Icons.arrow_upward,
                                              color: Colors.red, size: 16),
                                          const SizedBox(width: 4),
                                          Text('${user.totalPayments}'),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        children: [
                                          const Icon(Icons.arrow_downward,
                                              color: Colors.green, size: 16),
                                          const SizedBox(width: 4),
                                          Text('${user.totalCollections}'),
                                        ],
                                      ),
                                    ),
                                    DataCell(
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: user.activeSessions > 0
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.grey.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.devices,
                                              size: 16,
                                              color: user.activeSessions > 0
                                                  ? Colors.green
                                                  : Colors.grey,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${user.activeSessions}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: user.activeSessions > 0
                                                    ? Colors.green.shade700
                                                    : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      IconButton(
                                        icon: const Icon(Icons.more_vert),
                                        onPressed: () => _showActionsMenu(user),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}
