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
              if (selectedRole == UserRole.premium || (currentRole == UserRole.premium && selectedRole == UserRole.premium))
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
                            setStateDialog(() => selectedMonths = selected ? 1 : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('2 meses'),
                          selected: selectedMonths == 2,
                          onSelected: (selected) {
                            setStateDialog(() => selectedMonths = selected ? 2 : null);
                          },
                        ),
                        ChoiceChip(
                          label: const Text('3 meses'),
                          selected: selectedMonths == 3,
                          onSelected: (selected) {
                            setStateDialog(() => selectedMonths = selected ? 3 : null);
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
            ? null  // Mantener la fecha de inicio original
            : now.toIso8601String();
        updates['subscription_end'] = endDate.toIso8601String();
        updates['subscription_cancelled'] = false;
      }
      
      await _supabase.from('profiles').update(updates).eq('id', user.id);

      if (!mounted) return;
      
      String message = 'Rol actualizado exitosamente';
      if (months != null) {
        message += '\n+$months ${months == 1 ? 'mes' : 'meses'} Premium agregado${months > 1 ? 's' : ''}';
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
      await _supabase
          .from('user_sessions')
          .delete()
          .eq('user_id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesiones cerradas exitosamente')),
      );

      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e,
          fallback: 'Error al cerrar sesiones');
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
              final device = session['device_info'] as String? ?? 'Dispositivo desconocido';
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
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)));
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
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      final payments = await _supabase
          .from('payments')
          .select()
          .eq('user_id', user.id);
      
      // Obtener todos los movimientos de los pagos del usuario
      final paymentIds = (payments as List).map((p) => p['id']).toList();
      List<dynamic> movements = [];
      if (paymentIds.isNotEmpty) {
        movements = await _supabase
            .from('payments_movements')
            .select()
            .in_('payment_id', paymentIds);
      }
      
      final sessions = await _supabase
          .from('user_sessions')
          .select()
          .eq('user_id', user.id);
      
      // Generar SQL
      final sql = StringBuffer();
      sql.writeln('-- Backup de datos del usuario: ${user.email}');
      sql.writeln('-- Fecha: ${DateTime.now().toIso8601String()}');
      sql.writeln('-- ID Usuario: ${user.id}');
      sql.writeln();
      
      // Profile
      sql.writeln('-- ============ PROFILE ============');
      sql.writeln('INSERT INTO profiles (id, email, full_name, company, role, subscription_start, subscription_end, subscription_cancelled, interface_preference, updated_at, created_at)');
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
          sql.writeln('INSERT INTO payments (id, user_id, entity, amount, type, description, created_at, end_date)');
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
          sql.writeln('INSERT INTO payments_movements (id, payment_id, amount, movement_type, created_at)');
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
          sql.writeln('INSERT INTO user_sessions (id, user_id, device_info, created_at)');
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
      await _saveAndShareFile(
        sql.toString(),
        'backup_user_${user.id}_${DateTime.now().millisecondsSinceEpoch}.sql'
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup del usuario generado exitosamente')),
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
          '• Estructura de todas las tablas\n'
          '• Todos los usuarios y perfiles\n'
          '• Todos los pagos y movimientos\n'
          '• Todas las sesiones activas\n\n'
          'Este proceso puede tardar varios minutos.'
        ),
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
    
    try {
      setState(() => _loading = true);
      
      // Obtener todos los datos
      final profiles = await _supabase.from('profiles').select();
      final payments = await _supabase.from('payments').select();
      final movements = await _supabase.from('payments_movements').select();
      final sessions = await _supabase.from('user_sessions').select();
      
      final sql = StringBuffer();
      sql.writeln('-- ============================================');
      sql.writeln('-- BACKUP COMPLETO - SEPAGOS APP');
      sql.writeln('-- Fecha: ${DateTime.now().toIso8601String()}');
      sql.writeln('-- ============================================');
      sql.writeln();
      
      // Estructura de tablas
      sql.writeln('-- ============ ESTRUCTURA DE TABLAS ============');
      sql.writeln();
      
      // Profiles table
      sql.writeln('CREATE TABLE IF NOT EXISTS profiles (');
      sql.writeln('  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,');
      sql.writeln('  email TEXT,');
      sql.writeln('  full_name TEXT,');
      sql.writeln('  company TEXT,');
      sql.writeln('  role TEXT DEFAULT \'free\',');
      sql.writeln('  subscription_start TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  subscription_end TIMESTAMP WITH TIME ZONE,');
      sql.writeln('  subscription_cancelled BOOLEAN DEFAULT false,');
      sql.writeln('  interface_preference TEXT DEFAULT \'prestamista\',');
      sql.writeln('  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()');
      sql.writeln(');');
      sql.writeln();
      
      // Payments table
      sql.writeln('CREATE TABLE IF NOT EXISTS payments (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,');
      sql.writeln('  entity TEXT NOT NULL,');
      sql.writeln('  amount NUMERIC(15,2) NOT NULL DEFAULT 0,');
      sql.writeln('  type TEXT NOT NULL CHECK (type IN (\'cobro\', \'pago\')),');
      sql.writeln('  description TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),');
      sql.writeln('  end_date TIMESTAMP WITH TIME ZONE');
      sql.writeln(');');
      sql.writeln();
      
      // Payments movements table
      sql.writeln('CREATE TABLE IF NOT EXISTS payments_movements (');
      sql.writeln('  id BIGSERIAL PRIMARY KEY,');
      sql.writeln('  payment_id BIGINT NOT NULL REFERENCES payments(id) ON DELETE CASCADE,');
      sql.writeln('  amount NUMERIC(15,2) NOT NULL,');
      sql.writeln('  movement_type TEXT NOT NULL CHECK (movement_type IN (\'initial\', \'increment\', \'reduction\')),');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()');
      sql.writeln(');');
      sql.writeln();
      
      // User sessions table
      sql.writeln('CREATE TABLE IF NOT EXISTS user_sessions (');
      sql.writeln('  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),');
      sql.writeln('  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,');
      sql.writeln('  device_info TEXT,');
      sql.writeln('  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()');
      sql.writeln(');');
      sql.writeln();
      
      // Índices
      sql.writeln('-- ============ ÍNDICES ============');
      sql.writeln('CREATE INDEX IF NOT EXISTS idx_payments_user_id ON payments(user_id);');
      sql.writeln('CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);');
      sql.writeln('CREATE INDEX IF NOT EXISTS idx_movements_payment_id ON payments_movements(payment_id);');
      sql.writeln('CREATE INDEX IF NOT EXISTS idx_sessions_user_id ON user_sessions(user_id);');
      sql.writeln();
      
      // RLS Policies
      sql.writeln('-- ============ ROW LEVEL SECURITY ============');
      sql.writeln('ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE payments ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE payments_movements ENABLE ROW LEVEL SECURITY;');
      sql.writeln('ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;');
      sql.writeln();
      
      sql.writeln('-- Políticas para profiles');
      sql.writeln('CREATE POLICY "Users can view own profile" ON profiles FOR SELECT USING (auth.uid() = id);');
      sql.writeln('CREATE POLICY "Users can update own profile" ON profiles FOR UPDATE USING (auth.uid() = id);');
      sql.writeln();
      
      sql.writeln('-- Políticas para payments');
      sql.writeln('CREATE POLICY "Users can view own payments" ON payments FOR SELECT USING (auth.uid() = user_id);');
      sql.writeln('CREATE POLICY "Users can insert own payments" ON payments FOR INSERT WITH CHECK (auth.uid() = user_id);');
      sql.writeln('CREATE POLICY "Users can update own payments" ON payments FOR UPDATE USING (auth.uid() = user_id);');
      sql.writeln('CREATE POLICY "Users can delete own payments" ON payments FOR DELETE USING (auth.uid() = user_id);');
      sql.writeln();
      
      sql.writeln('-- Políticas para payments_movements');
      sql.writeln('CREATE POLICY "Users can view movements of own payments" ON payments_movements FOR SELECT');
      sql.writeln('  USING (EXISTS (SELECT 1 FROM payments WHERE payments.id = payments_movements.payment_id AND payments.user_id = auth.uid()));');
      sql.writeln('CREATE POLICY "Users can insert movements to own payments" ON payments_movements FOR INSERT');
      sql.writeln('  WITH CHECK (EXISTS (SELECT 1 FROM payments WHERE payments.id = payments_movements.payment_id AND payments.user_id = auth.uid()));');
      sql.writeln();
      
      sql.writeln('-- Políticas para user_sessions');
      sql.writeln('CREATE POLICY "Users can view own sessions" ON user_sessions FOR SELECT USING (auth.uid() = user_id);');
      sql.writeln('CREATE POLICY "Users can insert own sessions" ON user_sessions FOR INSERT WITH CHECK (auth.uid() = user_id);');
      sql.writeln('CREATE POLICY "Users can delete own sessions" ON user_sessions FOR DELETE USING (auth.uid() = user_id);');
      sql.writeln();
      
      // Datos
      sql.writeln('-- ============ DATOS ============');
      sql.writeln();
      
      // Profiles
      if (profiles.isNotEmpty) {
        sql.writeln('-- Profiles (${(profiles as List).length} registros)');
        for (final profile in profiles) {
          sql.writeln('INSERT INTO profiles (id, email, full_name, company, role, subscription_start, subscription_end, subscription_cancelled, interface_preference, updated_at, created_at)');
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
          sql.writeln(')');
          sql.writeln('ON CONFLICT (id) DO NOTHING;');
          sql.writeln();
        }
      }
      
      // Payments
      if (payments.isNotEmpty) {
        sql.writeln('-- Payments (${(payments as List).length} registros)');
        for (final payment in payments) {
          sql.writeln('INSERT INTO payments (id, user_id, entity, amount, type, description, created_at, end_date)');
          sql.writeln('VALUES (');
          sql.writeln("  ${payment['id']},");
          sql.writeln("  '${payment['user_id']}',");
          sql.writeln("  ${_sqlValue(payment['entity'])},");
          sql.writeln("  ${payment['amount']},");
          sql.writeln("  ${_sqlValue(payment['type'])},");
          sql.writeln("  ${_sqlValue(payment['description'])},");
          sql.writeln("  ${_sqlValue(payment['created_at'])},");
          sql.writeln("  ${_sqlValue(payment['end_date'])}");
          sql.writeln(')');
          sql.writeln('ON CONFLICT (id) DO NOTHING;');
          sql.writeln();
        }
      }
      
      // Movements
      if (movements.isNotEmpty) {
        sql.writeln('-- Payment Movements (${(movements as List).length} registros)');
        for (final movement in movements) {
          sql.writeln('INSERT INTO payments_movements (id, payment_id, amount, movement_type, created_at)');
          sql.writeln('VALUES (');
          sql.writeln("  ${movement['id']},");
          sql.writeln("  ${movement['payment_id']},");
          sql.writeln("  ${movement['amount']},");
          sql.writeln("  ${_sqlValue(movement['movement_type'])},");
          sql.writeln("  ${_sqlValue(movement['created_at'])}");
          sql.writeln(')');
          sql.writeln('ON CONFLICT (id) DO NOTHING;');
          sql.writeln();
        }
      }
      
      // Sessions
      if (sessions.isNotEmpty) {
        sql.writeln('-- User Sessions (${(sessions as List).length} registros)');
        for (final session in sessions as List) {
          sql.writeln('INSERT INTO user_sessions (id, user_id, device_info, created_at)');
          sql.writeln('VALUES (');
          sql.writeln("  '${session['id']}',");
          sql.writeln("  '${session['user_id']}',");
          sql.writeln("  ${_sqlValue(session['device_info'])},");
          sql.writeln("  ${_sqlValue(session['created_at'])}");
          sql.writeln(')');
          sql.writeln('ON CONFLICT (id) DO NOTHING;');
          sql.writeln();
        }
      }
      
      sql.writeln('-- ============================================');
      sql.writeln('-- BACKUP COMPLETADO EXITOSAMENTE');
      sql.writeln('-- Total perfiles: ${(profiles as List).length}');
      sql.writeln('-- Total pagos: ${(payments as List).length}');
      sql.writeln('-- Total movimientos: ${(movements as List).length}');
      sql.writeln('-- Total sesiones: ${(sessions as List).length}');
      sql.writeln('-- ============================================');
      
      // Guardar archivo
      await _saveAndShareFile(
        sql.toString(),
        'backup_completo_sepagos_${DateTime.now().millisecondsSinceEpoch}.sql'
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup completo generado: ${(profiles as List).length} usuarios, ${(payments as List).length} pagos'),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar backup completo: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                                        borderRadius: BorderRadius.circular(8),
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
                                        borderRadius: BorderRadius.circular(8),
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
