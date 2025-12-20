import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PaymentsListPage extends StatefulWidget {
  const PaymentsListPage({super.key});

  @override
  State<PaymentsListPage> createState() => _PaymentsListPageState();
}

class Payment {
  final String id;
  final String client;
  final double amount;
  final DateTime createdAt;

  Payment({required this.id, required this.client, required this.amount, required this.createdAt});

  factory Payment.fromMap(Map<String, dynamic> m) {
    return Payment(
      id: m['id'].toString(),
      client: m['client_name'] ?? '',
      amount: (m['amount'] != null) ? (double.tryParse(m['amount'].toString()) ?? 0.0) : 0.0,
      createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}

class _PaymentsListPageState extends State<PaymentsListPage> {
  final _supabase = Supabase.instance.client;
  List<Payment> _items = [];
  bool _loading = false;
  int _page = 0;
  final int _pageSize = 5;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch({bool next = false}) async {
    if (next) _page++;
    setState(() => _loading = true);
    final from = _page * _pageSize;
    try {
        final res = await _supabase.from('payments').select().order('created_at', ascending: false).range(from, from + _pageSize - 1);
        final data = (res as List<dynamic>? ?? []);
      final items = data.map((e) => Payment.fromMap(e as Map<String, dynamic>)).toList();
      setState(() => _items = [..._items, ...items]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(String id) async {
    setState(() => _loading = true);
    try {
      await _supabase.from('payments').delete().eq('id', id);
      setState(() => _items.removeWhere((i) => i.id == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showEditDialog({Payment? p}) async {
    final clientCtrl = TextEditingController(text: p?.client ?? 'Cliente Uno');
    final amountCtrl = TextEditingController(text: p != null ? p.amount.toStringAsFixed(0) : '200000');
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p == null ? 'Agregar pago' : 'Editar pago'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: clientCtrl,
                decoration: const InputDecoration(labelText: 'Cliente'),
                validator: (v) => (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
              ),
              TextFormField(
                controller: amountCtrl,
                decoration: const InputDecoration(labelText: 'Monto'),
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || double.tryParse(v) == null) ? 'Monto inválido' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final client = clientCtrl.text.trim();
              final amount = double.parse(amountCtrl.text);
              Navigator.of(context).pop(true);
              if (p == null) {
                await _create(client, amount);
              } else {
                await _update(p.id, client, amount);
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result == true) {
      // reload list
      setState(() {
        _items = [];
        _page = 0;
      });
      await _fetch();
    }
  }

  Future<void> _create(String client, double amount) async {
    setState(() => _loading = true);
    try {
      await _supabase.from('payments').insert({
        'client_name': client,
        'amount': amount,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago agregado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(String id, String client, double amount) async {
    setState(() => _loading = true);
    try {
      await _supabase.from('payments').update({
        'client_name': client,
        'amount': amount,
      }).eq('id', id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pago actualizado')));
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
      appBar: AppBar(title: const Text('Lista de Pagos / Cobros')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Center(
              child: IconButton(
                iconSize: 48,
                onPressed: () => _showEditDialog(),
                icon: const CircleAvatar(child: Icon(Icons.add)),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty && !_loading
                  ? const Center(child: Text('Sin registros'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final it = _items[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(it.client, style: const TextStyle(color: Colors.white)),
                                    Text('\$${it.amount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 32),
                              onPressed: () => _delete(it.id),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.black, size: 28),
                              onPressed: () => _showEditDialog(p: it),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (_loading) const CircularProgressIndicator(),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : () => _fetch(next: true),
              child: const Text('Ver Más'),
            )
          ],
        ),
      ),
    );
  }
}
