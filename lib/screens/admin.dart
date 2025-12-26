import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  UserInfo({
    required this.id,
    required this.email,
    this.fullName,
    this.company,
    required this.role,
    required this.createdAt,
    required this.totalPayments,
    required this.totalCollections,
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

    final result = await showDialog<UserRole>(
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
                  setStateDialog(() => selectedRole = value);
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
                  setStateDialog(() => selectedRole = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(selectedRole),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result == currentRole) return;

    try {
      await _supabase.from('profiles').update({
        'role': result.value,
      }).eq('id', user.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol actualizado exitosamente')),
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
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Usuario')),
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Rol')),
                              DataColumn(label: Text('Registro')),
                              DataColumn(label: Text('Pagos')),
                              DataColumn(label: Text('Cobros')),
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
                      ],
                    ),
            ),
    );
  }
}
