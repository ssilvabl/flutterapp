import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/error_messages.dart';
import '../constants/user_roles.dart';
import '../utils/interface_labels.dart';
import '../utils/preference_provider.dart';
import 'login.dart';
import 'profile_edit_dialog.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? _user;
  bool _loading = false;
  String? _fullName;
  String? _company;
  UserRole _userRole = UserRole.free;
  InterfacePreference _interfacePreference = InterfacePreference.prestamista;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  void _loadUser() {
    final res = Supabase.instance.client.auth.currentUser;
    setState(() => _user = res);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final uid = _user?.id;
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .single();
      if (res != null) {
        setState(() {
          _fullName = res['full_name'] as String?;
          _company = res['company'] as String?;
          final roleStr = res['role'] as String? ?? 'free';
          _userRole = UserRoleExtension.fromString(roleStr);
          final prefStr = res['interface_preference'] as String?;
          _interfacePreference =
              InterfacePreferenceExtension.fromString(prefStr);
        });
      }
    } catch (_) {}
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  Future<void> _editField(String label, String? initial) async {
    final result = await showDialog<String?>(
        context: context,
        builder: (_) =>
            ProfileEditDialog(label: label, initialValue: initial ?? ''));
    if (result == null) return;
    final uid = _user?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id': uid,
        label == 'Nombre' ? 'full_name' : 'company': result,
      });
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo guardar el perfil');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _changePassword() async {
    final email = _user?.email;
    if (email == null) return;

    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (dialogCtx, setStateDialog) {
          return AlertDialog(
            title: const Text('Cambiar contraseña'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: currentCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Contraseña actual'),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Ingresa tu contraseña actual'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: newCtrl,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Nueva contraseña'),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Mínimo 6 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirmar nueva contraseña'),
                    validator: (v) => v != newCtrl.text ? 'No coinciden' : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed:
                      saving ? null : () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setStateDialog(() => saving = true);
                        try {
                          await Supabase.instance.client.auth
                              .signInWithPassword(
                                  email: email,
                                  password: currentCtrl.text.trim());
                          await Supabase.instance.client.auth.updateUser(
                              UserAttributes(password: newCtrl.text.trim()));
                          if (mounted) {
                            Navigator.of(dialogCtx).pop(true);
                          }
                        } catch (e) {
                          setStateDialog(() => saving = false);
                          final msg = friendlySupabaseMessage(e,
                              fallback: 'No se pudo cambiar la contraseña');
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(msg)));
                        }
                      },
                child: saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar'),
              ),
            ],
          );
        });
      },
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contraseña actualizada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2323),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
                height: 80,
                width: double.infinity,
                decoration: const BoxDecoration(color: Color(0xFF1F2323))),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.only(topLeft: Radius.circular(40))),
              child: _user == null
                  ? const Center(child: Text('No hay usuario logueado'))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                            child: Text('Perfil',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium)),
                        const SizedBox(height: 18),
                        _buildField('Nombre', _fullName ?? ''),
                        const SizedBox(height: 12),
                        _buildField('Correo electrónico', _user!.email ?? '',
                            editable: false),
                        const SizedBox(height: 12),
                        _buildField('Contraseña', '******', editable: false),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _loading ? null : _changePassword,
                            child: const Text('Cambiar contraseña'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildField('Nombre Empresa', _company ?? ''),
                        const SizedBox(height: 24),
                        _buildInterfacePreferenceSelector(),
                        const SizedBox(height: 12),
                        _buildRoleField(),
                      ],
                    ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, String value, {bool editable = true}) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey[300]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(),
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              Text(value, style: const TextStyle(fontSize: 16)),
            ]),
          ),
        ),
        if (editable) ...[
          const SizedBox(width: 8),
          IconButton(
              onPressed: () => _editField(
                  label == 'Nombre' ? 'Nombre' : 'Nombre Empresa',
                  label == 'Nombre' ? _fullName : _company),
              icon: const Icon(Icons.edit_outlined)),
        ]
      ],
    );
  }

  Future<void> _updateInterfacePreference(InterfacePreference newPref) async {
    final uid = _user?.id;
    if (uid == null) return;

    try {
      // Actualizar en el provider (esto hace el update en la BD y notifica a toda la app)
      final preferenceProvider = PreferenceInheritedWidget.of(context);
      if (preferenceProvider != null) {
        await preferenceProvider.updatePreference(newPref);
      }

      setState(() {
        _interfacePreference = newPref;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Preferencia actualizada - Los cambios se aplicaron en toda la app')),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e,
          fallback: 'Error al actualizar preferencia');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _buildInterfacePreferenceSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '¿Qué tipo de interfaz prefieres?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Esto cambiará cómo se muestran los nombres en la aplicación',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<InterfacePreference>(
            value: _interfacePreference,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: InterfacePreference.values.map((pref) {
              final labels = InterfaceLabels(pref);
              return DropdownMenuItem(
                value: pref,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pref.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${labels.cobros} / ${labels.pagos}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      _updateInterfacePreference(value);
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildRoleField() {
    final roleDisplayNames = {
      UserRole.admin: 'Administrador',
      UserRole.premium: 'Premium',
      UserRole.free: 'Gratis',
    };

    final roleColors = {
      UserRole.admin: Colors.red.shade100,
      UserRole.premium: Colors.amber.shade100,
      UserRole.free: Colors.grey.shade300,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: roleColors[_userRole],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PLAN',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      _userRole == UserRole.admin
                          ? Icons.admin_panel_settings
                          : _userRole == UserRole.premium
                              ? Icons.star
                              : Icons.person,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      roleDisplayNames[_userRole] ?? 'Gratis',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
