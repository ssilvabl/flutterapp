import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PaymentDetailsPage extends StatefulWidget {
  final Map<String, dynamic> payment;
  const PaymentDetailsPage({super.key, required this.payment});

  @override
  State<PaymentDetailsPage> createState() => _PaymentDetailsPageState();
}

class Movement {
  final String id;
  final String movementType; // 'initial','increment','reduction'
  final double amount;
  final DateTime createdAt;
  final String? note;

  Movement({required this.id, required this.movementType, required this.amount, required this.createdAt, this.note});

  factory Movement.fromMap(Map<String, dynamic> m) {
    return Movement(
      id: m['id'].toString(),
      movementType: (m['movement_type'] ?? '').toString(),
      amount: (m['amount'] != null) ? (double.tryParse(m['amount'].toString()) ?? 0.0) : 0.0,
      createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
      note: m['note'] as String?,
    );
  }
}

class _PaymentDetailsPageState extends State<PaymentDetailsPage> {
  final _supabase = Supabase.instance.client;
  List<Movement> _moves = [];
  bool _loading = false;
  String? _profileName;
  StreamSubscription<List<Map<String, dynamic>>>? _movesSub;

  @override
  void initState() {
    super.initState();
    _loadMovements();
    _loadProfile();
    _setupRealtime();
  }

  Future<void> _loadMovements() async {
    setState(() => _loading = true);
    try {
      final pid = widget.payment['id']?.toString();
      final res = await _supabase.from('payments_movements').select().eq('payment_id', pid).order('created_at', ascending: false);
      final List<Map<String, dynamic>> data = (res is List) ? List<Map<String, dynamic>>.from(res) : <Map<String, dynamic>>[];
      setState(() => _moves = data.map((e) => Movement.fromMap(e)).toList());
    } catch (e) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadProfile() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final res = await _supabase.from('profiles').select().eq('id', uid).maybeSingle();
      if (res != null) {
        setState(() => _profileName = res['company'] ?? res['full_name']);
      }
    } catch (_) {}
  }

  void _setupRealtime() {
    final pid = widget.payment['id']?.toString();
    if (pid == null) return;
    _movesSub = _supabase
        .from('payments_movements')
        .stream(primaryKey: ['id'])
        .eq('payment_id', pid)
        .order('created_at', ascending: false)
        .listen((data) {
      if (!mounted) return;
      setState(() {
        _moves = data.map((e) => Movement.fromMap(e)).toList();
      });
    });
  }

  @override
  void dispose() {
    _movesSub?.cancel();
    super.dispose();
  }

  double _sumByType(String type) => _moves.where((m) => m.movementType == type).fold(0.0, (s, m) => s + m.amount);

  Future<void> _sharePdf() async {
    final pdf = pw.Document();
    final entity = widget.payment['entity']?.toString() ?? '';
    final profile = _profileName ?? '';
    final amountVal = (widget.payment['amount'] is num) ? (widget.payment['amount'] as num).toDouble() : double.tryParse(widget.payment['amount']?.toString() ?? '0') ?? 0.0;


    pdf.addPage(pw.MultiPage(
      build: (pw.Context ctx) => [
        pw.Header(level: 0, child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (profile.isNotEmpty) pw.Text(profile, style: const pw.TextStyle(fontSize: 18)),
          pw.Text(entity, style: const pw.TextStyle(fontSize: 16)),
        ])),
        pw.SizedBox(height: 6),
        pw.Paragraph(text: 'Monto Actual: \$${_formatAmount(amountVal)}'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(context: ctx,
          headers: ['Fecha', 'Tipo', 'Valor'],
          data: _moves.map((m) {
            final tipo = m.movementType == 'initial'
                ? 'Inicial'
                : m.movementType == 'increment'
                    ? 'Incremento'
                    : m.movementType == 'reduction'
                        ? 'Reducción'
                        : m.movementType;
            return [m.createdAt.toIso8601String().substring(0, 10), tipo, '\$${_formatAmount(m.amount)}'];
          }).toList(),
        ),
        pw.SizedBox(height: 10),
        pw.Paragraph(text: 'Monto Inicial: \$${_formatAmount(_sumByType('initial'))}'),
        pw.Paragraph(text: 'Total Incrementos: \$${_formatAmount(_sumByType('increment'))}'),
        pw.Paragraph(text: 'Total Reducciones: \$${_formatAmount(_sumByType('reduction'))}'),
        pw.Paragraph(text: 'Monto Final: \$${_formatAmount(amountVal)}'),
      ],
    ));

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'factura_$entity.pdf');
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Estás seguro de que deseas eliminar "${widget.payment['entity']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deletePayment();
    }
  }

  Future<void> _deletePayment() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      final paymentId = widget.payment['id']?.toString();
      
      if (userId == null || paymentId == null) {
        throw Exception('No autorizado');
      }

      await _supabase
          .from('payments')
          .delete()
          .eq('id', paymentId)
          .eq('user_id', userId);

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pago eliminado exitosamente')),
      );

      // Volver a la pantalla anterior
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al eliminar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.payment['entity']?.toString() ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.of(context).pop({'action': 'edit', 'payment': widget.payment});
            },
            tooltip: 'Editar',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _confirmDelete,
            tooltip: 'Eliminar',
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _sharePdf,
            tooltip: 'Exportar PDF',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monto Actual: \$${_formatAmount((widget.payment['amount'] is num) ? (widget.payment['amount'] as num).toDouble() : double.tryParse(widget.payment['amount']?.toString() ?? '0') ?? 0.0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Fecha Inicio: ${_formatDate(widget.payment['createdAt'] is DateTime ? widget.payment['createdAt'] as DateTime : DateTime.tryParse(widget.payment['created_at']?.toString() ?? '') ?? DateTime.now())}'),
          if ((widget.payment['endDate'] is DateTime ? widget.payment['endDate'] as DateTime : DateTime.tryParse(widget.payment['end_date']?.toString() ?? '') ) != null) Text('Fecha Fin: ${_formatDate(widget.payment['endDate'] is DateTime ? widget.payment['endDate'] as DateTime : DateTime.tryParse(widget.payment['end_date']?.toString() ?? '')!)}'),
          const SizedBox(height: 12),
          Text('Descripción: ${widget.payment['description'] ?? 'N/A'}'),
          const SizedBox(height: 16),
          Row(children: [
            ElevatedButton.icon(onPressed: _loadMovements, icon: const Icon(Icons.refresh), label: const Text('Actualizar')),
          ]),
          const SizedBox(height: 8),
          const Text('Historial de Movimientos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _loading ? const Center(child: CircularProgressIndicator()) : Expanded(
            child: _moves.isEmpty ? const Text('Sin movimientos') : ListView.separated(
              itemCount: _moves.length,
              separatorBuilder: (_,__) => const Divider(),
              itemBuilder: (context, index) {
                final m = _moves[index];
                final tipo = m.movementType == 'initial'
                    ? 'Inicial'
                    : m.movementType == 'increment'
                        ? 'Incremento'
                        : m.movementType == 'reduction'
                            ? 'Reducción'
                            : m.movementType;
                return ListTile(
                  title: Text(tipo),
                  subtitle: Text(_formatDate(m.createdAt)),
                  trailing: Text('\$${_formatAmount(m.amount)}'),
                );
              }
            )
          ),
        ]),
      ),
    );
  }

  String _formatAmount(double value) {
    final s = value.toStringAsFixed(0);
    final buffer = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buffer.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        buffer.write('.');
        count = 0;
      }
    }
    return buffer.toString().split('').reversed.join();
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';
}
