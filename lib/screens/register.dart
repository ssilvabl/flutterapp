import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/error_messages.dart';
import 'pending_confirmation.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  // Remove date of birth; use confirm password instead
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final confirm = _confirmPasswordController.text;

    // Cache messenger and navigator to avoid using BuildContext across async gaps
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    if (password != confirm) {
      if (mounted)
        messenger.showSnackBar(
            const SnackBar(content: Text('Las contraseñas no coinciden')));
      setState(() => _loading = false);
      return;
    }

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      final ok = res.user != null;
      if (!mounted) return;
      if (ok) {
        // create profile row
        final userId = res.user?.id;
        if (userId != null) {
          try {
            await Supabase.instance.client.from('profiles').insert({
              'id': userId,
              'full_name': name,
              'email': email,
              'role': 'free',
            });
            debugPrint('Profile created successfully for user: $userId');
          } catch (e) {
            debugPrint('Error creating profile: $e');
            // No bloqueamos el registro si falla el perfil
            // El perfil se puede crear después manualmente
          }
        }

        // Navigate to pending confirmation
        navigator.pushReplacement(MaterialPageRoute(
            builder: (_) => PendingConfirmationPage(
                  email: email,
                  password: password,
                )));
      } else {
        if (!mounted) return;
        messenger.showSnackBar(
            const SnackBar(content: Text('No se pudo crear la cuenta')));
      }
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo crear la cuenta');
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: const BoxDecoration(color: Color(0xFF1F2323)),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.only(topLeft: Radius.circular(40))),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                        child: Text('Registrarse',
                            style: Theme.of(context).textTheme.headlineMedium)),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        filled: true,
                        fillColor: Colors.grey[300],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 18),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
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
                        labelText: 'Password',
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
                        if (v == null || v.isEmpty)
                          return 'Ingresa una contraseña';
                        if (v.length < 6)
                          return 'La contraseña debe tener al menos 6 caracteres';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
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
                        if (v == null || v.isEmpty)
                          return 'Confirma la contraseña';
                        if (v != _passwordController.text)
                          return 'Las contraseñas no coinciden';
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: _loading ? null : _signUp,
                      child: _loading
                          ? const CircularProgressIndicator()
                          : const Text('Sign up'),
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
