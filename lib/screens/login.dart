import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/error_messages.dart';
import '../utils/session_manager.dart';
import 'payments_list.dart';
import 'preference_selection.dart';
import 'register.dart';
import 'package:intl/intl.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final ok = res.session != null || res.user != null;
      if (!mounted) return;

      if (ok && res.user != null) {
        // Obtener rol y preferencia del usuario
        final profileResponse = await Supabase.instance.client
            .from('profiles')
            .select('role, interface_preference')
            .eq('id', res.user!.id)
            .single();

        final userRole = profileResponse['role'] as String? ?? 'free';
        final interfacePreference =
            profileResponse['interface_preference'] as String?;

        // Verificar límite de sesiones
        final sessionCheck =
            await SessionManager.checkSessionLimit(res.user!.id, userRole);

        if (!sessionCheck.canLogin) {
          // Mostrar diálogo para cerrar sesiones antiguas
          if (!mounted) return;
          final shouldCloseSessions = await _showSessionLimitDialog(
            sessionCheck.activeSessions,
            sessionCheck.maxSessions,
            sessionCheck.sessions,
          );

          if (shouldCloseSessions == true) {
            // Cerrar sesiones antiguas y crear nueva sesión
            await SessionManager.removeSessions(
              sessionCheck.sessions.map((s) => s['id'] as String).toList(),
            );
            await SessionManager.createSession();

            if (!mounted) return;
            // Verificar si necesita elegir preferencia
            if (interfacePreference == null || interfacePreference.isEmpty) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                    builder: (_) => const PreferenceSelectionPage()),
                (route) => false,
              );
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const PaymentsListPage()),
                (route) => false,
              );
            }
          } else {
            // Usuario canceló, cerrar sesión actual
            await Supabase.instance.client.auth.signOut();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Inicio de sesión cancelado')),
            );
          }
        } else {
          // Crear nueva sesión
          await SessionManager.createSession();

          if (!mounted) return;
          // Verificar si necesita elegir preferencia
          if (interfacePreference == null || interfacePreference.isEmpty) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => const PreferenceSelectionPage()),
              (route) => false,
            );
          } else {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const PaymentsListPage()),
              (route) => false,
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo iniciar sesión')));
      }
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo iniciar sesión');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showSessionLimitDialog(
    int activeSessions,
    int maxSessions,
    List<Map<String, dynamic>> sessions,
  ) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Límite de sesiones alcanzado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tienes $activeSessions sesiones activas y tu límite es de $maxSessions.',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Sesiones activas:'),
              const SizedBox(height: 8),
              ...sessions.map((session) {
                final deviceInfo = session['device_info'] as String? ??
                    'Dispositivo desconocido';
                final lastActivity = session['last_activity'] as String?;
                String activityText = '';

                if (lastActivity != null) {
                  try {
                    final dateTime = DateTime.parse(lastActivity);
                    activityText =
                        DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
                  } catch (e) {
                    activityText = 'Fecha desconocida';
                  }
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      const Icon(Icons.devices, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(deviceInfo,
                                style: const TextStyle(fontSize: 12)),
                            Text(
                              'Última actividad: $activityText',
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              const Text(
                '¿Deseas cerrar las sesiones anteriores y continuar?',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Cerrar sesiones y continuar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            // dark banner with icon
            Container(
              height: 220,
              width: double.infinity,
              decoration: const BoxDecoration(color: Color(0xFF1F2323)),
              child: const Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.green,
                  child:
                      Icon(Icons.attach_money, color: Colors.white, size: 36),
                ),
              ),
            ),
            // white rounded card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(40)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Text('Inicio de sesión',
                            style: Theme.of(context).textTheme.headlineMedium)),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        filled: true,
                        fillColor: Colors.grey[300],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Ingresa un email';
                        final regex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
                        if (!regex.hasMatch(v)) return 'Email inválido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        filled: true,
                        fillColor: Colors.grey[300],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                      ),
                      obscureText: true,
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Ingresa una contraseña';
                        }
                        if (v.length < 6) {
                          return 'La contraseña debe tener al menos 6 caracteres';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8))),
                      onPressed: _loading ? null : _signIn,
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text('Iniciar sesión'),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const RegisterPage())),
                        child: const Text('¿No tienes cuenta? Regístrate'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
