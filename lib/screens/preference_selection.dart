import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/interface_labels.dart';
import 'payments_list.dart';

class PreferenceSelectionPage extends StatefulWidget {
  const PreferenceSelectionPage({super.key});

  @override
  State<PreferenceSelectionPage> createState() =>
      _PreferenceSelectionPageState();
}

class _PreferenceSelectionPageState extends State<PreferenceSelectionPage> {
  InterfacePreference? _selectedPreference;
  bool _loading = false;

  Future<void> _savePreference() async {
    if (_selectedPreference == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una opción')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      await Supabase.instance.client.from('profiles').update({
        'interface_preference': _selectedPreference!.value,
      }).eq('id', uid);

      if (!mounted) return;

      // Navegar a la pantalla principal
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PaymentsListPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar preferencia: $e')),
      );
      setState(() => _loading = false);
    }
  }

  Widget _buildOptionCard(InterfacePreference preference) {
    final labels = InterfaceLabels(preference);
    final isSelected = _selectedPreference == preference;

    IconData icon;
    Color color;
    String description;

    switch (preference) {
      case InterfacePreference.prestamista:
        icon = Icons.account_balance;
        color = Colors.blue;
        description =
            'Ideal para gestionar préstamos y seguimiento de cobros a clientes';
        break;
      case InterfacePreference.personal:
        icon = Icons.person;
        color = Colors.green;
        description =
            'Perfecto para llevar el control de tus ingresos y gastos personales';
        break;
      case InterfacePreference.inversionista:
        icon = Icons.trending_up;
        color = Colors.purple;
        description =
            'Diseñado para inversionistas que manejan activos y pasivos';
        break;
    }

    return GestureDetector(
      onTap: _loading ? null : () {
        setState(() => _selectedPreference = preference);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preference.displayName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? color : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${labels.cobros} / ${labels.pagos}',
                        style: TextStyle(
                          fontSize: 14,
                          color: isSelected ? color : Colors.grey.shade600,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: color, size: 32)
                else
                  Icon(Icons.circle_outlined,
                      color: Colors.grey.shade400, size: 32),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                '¡Bienvenido!',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2323),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '¿Qué tipo de interfaz prefieres?',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Esto personalizará cómo se muestran los nombres en toda la aplicación',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: ListView(
                  children: [
                    _buildOptionCard(InterfacePreference.prestamista),
                    _buildOptionCard(InterfacePreference.personal),
                    _buildOptionCard(InterfacePreference.inversionista),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _savePreference,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F2323),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Continuar',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
