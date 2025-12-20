import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PendingConfirmationPage extends StatefulWidget {
  final String email;
  final String password;

  const PendingConfirmationPage({super.key, required this.email, required this.password});

  @override
  State<PendingConfirmationPage> createState() => _PendingConfirmationPageState();
}

class _PendingConfirmationPageState extends State<PendingConfirmationPage> {
  bool _loading = false;
  Timer? _timer;
  final String _status = 'Revisa tu correo y confirma la cuenta';

  @override
  void initState() {
    super.initState();
    // Optionally poll every few seconds to see if the user can login now
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tryRefresh());
  }

  Future<void> _tryRefresh() async {
    try {
      final signInRes = await Supabase.instance.client.auth.signInWithPassword(
        email: widget.email,
        password: widget.password,
      );
      if (signInRes.session != null || signInRes.user != null) {
        _timer?.cancel();
        if (!mounted) return;
        // navigate to root to let AuthGate decide
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (_) {
      // ignore network errors during polling
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      // re-trigger signUp to resend confirmation email (Supabase may allow this)
      await Supabase.instance.client.auth.signUp(email: widget.email, password: widget.password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Se reenvió el correo de confirmación')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tryLogin() async {
    setState(() => _loading = true);
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: widget.email,
        password: widget.password,
      );
      final ok = res.user != null || res.session != null;
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pushReplacementNamed('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aún no está confirmada la cuenta')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirma tu correo')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            Text(_status, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Text('Email: ${widget.email}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _resend,
              child: _loading ? const CircularProgressIndicator() : const Text('Reenviar correo'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loading ? null : _tryLogin,
              child: const Text('Ya confirmé - intentar iniciar sesión'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver'),
            )
          ],
        ),
      ),
    );
  }
}
