import 'package:flutter/material.dart';

class ProfileEditDialog extends StatelessWidget {
  final String label;
  final String initialValue;

  const ProfileEditDialog({super.key, required this.label, required this.initialValue});

  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: initialValue);
    return AlertDialog(
      title: Text('Editar $label'),
      content: TextField(controller: ctrl),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.of(context).pop(ctrl.text.trim()), child: const Text('Guardar')),
      ],
    );
  }
}
