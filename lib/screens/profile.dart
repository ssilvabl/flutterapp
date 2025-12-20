import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _user;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final res = Supabase.instance.client.auth.currentUser;
    setState(() => _user = res);
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _user == null
            ? const Center(child: Text('No hay usuario logueado'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Email: ${_user!.email ?? ''}'),
                  const SizedBox(height: 8),
                  Text('ID: ${_user!.id}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loading ? null : _logout,
                    child: _loading ? const CircularProgressIndicator() : const Text('Cerrar sesión'),
                  ),
                ],
              ),
      ),
    );
  }
}
