import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'payments_list.dart';

class PaymentDetailsPage extends StatefulWidget {
  final Map<String, dynamic> payment;
  final Function(Payment)? onEdit;
  const PaymentDetailsPage({super.key, required this.payment, this.onEdit});

  @override
  State<PaymentDetailsPage> createState() => _PaymentDetailsPageState();
}

class Movement {
  final String id;
  final String movementType; // 'initial','increment','reduction'
  final double amount;
  final DateTime createdAt;
  final String? note;

  Movement(
      {required this.id,
      required this.movementType,
      required this.amount,
      required this.createdAt,
      this.note});

  factory Movement.fromMap(Map<String, dynamic> m) {
    return Movement(
      id: m['id'].toString(),
      movementType: (m['movement_type'] ?? '').toString(),
      amount: (m['amount'] != null)
          ? (double.tryParse(m['amount'].toString()) ?? 0.0)
          : 0.0,
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
      final res = await _supabase
          .from('payments_movements')
          .select()
          .eq('payment_id', pid)
          .order('created_at', ascending: true);
      final List<Map<String, dynamic>> data = (res is List)
          ? List<Map<String, dynamic>>.from(res)
          : <Map<String, dynamic>>[];
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
      final res =
          await _supabase.from('profiles').select().eq('id', uid).maybeSingle();
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
        .order('created_at', ascending: true)
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

  double _sumByType(String type) => _moves
      .where((m) => m.movementType == type)
      .fold(0.0, (s, m) => s + m.amount);

  // Calcular el monto actual real basado en los movimientos
  double _calculateCurrentAmount() {
    final initial = _sumByType('initial');
    final increments = _sumByType('increment');
    final reductions = _sumByType('reduction');
    return initial + increments - reductions;
  }

  Future<void> _sharePdf() async {
    final pdf = pw.Document();
    final entity = widget.payment['entity']?.toString() ?? '';
    final profile = _profileName ?? '';

    // Usar el cálculo real basado en movimientos, no el valor de la base de datos
    final amountVal = _calculateCurrentAmount();

    // Colores personalizados usando PdfColor del paquete pdf
    final primaryBlue = PdfColor.fromHex('#2563eb');
    final lightBlue = PdfColor.fromHex('#dbeafe');
    final redColor = PdfColor.fromHex('#dc2626');
    final greenColor = PdfColor.fromHex('#16a34a');

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Encabezado azul
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(20),
              decoration: pw.BoxDecoration(
                color: primaryBlue,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    profile.isNotEmpty ? profile : 'SilvaSoft',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Factura - $entity',
                    style: const pw.TextStyle(
                      fontSize: 14,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Monto actual en cuadro azul claro
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: lightBlue,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Center(
                child: pw.Text(
                  'Monto Actual: \$${_formatAmount(amountVal)}',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: primaryBlue,
                  ),
                ),
              ),
            ),
            pw.SizedBox(height: 24),

            // Tabla de movimientos
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 1),
              children: [
                // Encabezado de la tabla
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: primaryBlue),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(12),
                      child: pw.Text(
                        'Fecha',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(12),
                      child: pw.Text(
                        'Tipo',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(12),
                      child: pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          'Valor',
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Filas de datos
                ..._moves.map((m) {
                  final tipo = m.movementType == 'initial'
                      ? 'Inicial'
                      : m.movementType == 'increment'
                          ? 'Incremento'
                          : m.movementType == 'reduction'
                              ? 'Reducción'
                              : m.movementType;

                  // Color según el tipo
                  final valorColor =
                      m.movementType == 'reduction' ? redColor : greenColor;

                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(12),
                        child: pw.Text(
                          m.createdAt.toIso8601String().substring(0, 10),
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(12),
                        child: pw.Text(
                          tipo,
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(12),
                        child: pw.Align(
                          alignment: pw.Alignment.centerRight,
                          child: pw.Text(
                            '\$${_formatAmount(m.amount)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: valorColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 24),

            // Resumen final
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 1),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Monto Inicial:',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        '\$${_formatAmount(_sumByType('initial'))}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Incrementos:',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        '\$${_formatAmount(_sumByType('increment'))}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Total Reducciones:',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        '\$${_formatAmount(_sumByType('reduction'))}',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),
                  pw.Divider(color: PdfColors.grey300),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Monto Final:',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                      pw.Text(
                        '\$${_formatAmount(amountVal)}',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: primaryBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'factura_$entity.pdf');
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text(
            '¿Estás seguro de que deseas eliminar "${widget.payment['entity']}"?'),
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

  Future<void> _editMovement(Movement movement) async {
    String selectedType = movement.movementType;
    DateTime selectedDate = movement.createdAt;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar Movimiento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Tipo de movimiento:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: selectedType,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'initial', child: Text('Inicial')),
                  DropdownMenuItem(
                      value: 'increment', child: Text('Incremento')),
                  DropdownMenuItem(
                      value: 'reduction', child: Text('Reducción')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedType = value);
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text('Fecha:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDate(selectedDate)),
                      const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Monto: \$${_formatAmount(movement.amount)}',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, {
                  'type': selectedType,
                  'date': selectedDate,
                });
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _updateMovement(
        movement.id,
        result['type'] as String,
        result['date'] as DateTime,
      );
    }
  }

  Future<void> _updateMovement(
      String movementId, String newType, DateTime newDate) async {
    try {
      print('🔄 Actualizando movimiento: $movementId');
      print('📝 Nuevo tipo: $newType');
      print('📅 Nueva fecha: ${newDate.toIso8601String()}');

      final response = await _supabase
          .from('payments_movements')
          .update({
            'movement_type': newType,
            'created_at': newDate.toIso8601String(),
          })
          .eq('id', movementId)
          .select();

      print('✅ Respuesta de actualización: $response');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento actualizado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Recargar movimientos manualmente para forzar actualización
      await _loadMovements();
    } catch (e) {
      print('❌ Error al actualizar movimiento: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _confirmDeleteMovement(Movement movement) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar Movimiento'),
        content:
            const Text('¿Estás seguro de que deseas eliminar este movimiento?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _deleteMovement(movement.id);
    }
  }

  Future<void> _deleteMovement(String movementId) async {
    try {
      await _supabase.from('payments_movements').delete().eq('id', movementId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movimiento eliminado exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadMovements();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
            onPressed: () async {
              if (widget.onEdit != null) {
                final payment = Payment(
                  id: widget.payment['id'].toString(),
                  entity: widget.payment['entity']?.toString() ?? '',
                  amount: (widget.payment['amount'] as num?)?.toDouble() ?? 0.0,
                  currentAmount:
                      (widget.payment['amount'] as num?)?.toDouble() ?? 0.0,
                  createdAt: widget.payment['createdAt'] as DateTime? ??
                      DateTime.now(),
                  endDate: widget.payment['endDate'] as DateTime?,
                  type: widget.payment['type']?.toString() ?? 'cobro',
                  description: widget.payment['description']?.toString(),
                );
                widget.onEdit!(payment);
                // Recargar movimientos después de editar
                await _loadMovements();
              }
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
      body: RefreshIndicator(
        onRefresh: _loadMovements,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monto Actual: \$${_formatAmount(_calculateCurrentAmount())}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
                'Fecha Inicio: ${_formatDate(widget.payment['createdAt'] is DateTime ? widget.payment['createdAt'] as DateTime : DateTime.tryParse(widget.payment['created_at']?.toString() ?? '') ?? DateTime.now())}'),
            if ((widget.payment['endDate'] is DateTime
                    ? widget.payment['endDate'] as DateTime
                    : DateTime.tryParse(
                        widget.payment['end_date']?.toString() ?? '')) !=
                null)
              Text(
                  'Fecha Fin: ${_formatDate(widget.payment['endDate'] is DateTime ? widget.payment['endDate'] as DateTime : DateTime.tryParse(widget.payment['end_date']?.toString() ?? '')!)}'),
            const SizedBox(height: 12),
            Text('Descripción: ${widget.payment['description'] ?? 'N/A'}'),
            const SizedBox(height: 16),
            const Text('Historial de Movimientos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : _moves.isEmpty
                    ? const Text('Sin movimientos')
                    : ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _moves.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, index) {
                          final m = _moves[index];
                          final tipo = m.movementType == 'initial'
                              ? 'Inicial'
                              : m.movementType == 'increment'
                                  ? 'Incremento'
                                  : m.movementType == 'reduction'
                                      ? 'Reducción'
                                      : m.movementType;

                          // Definir color según el tipo de movimiento
                          Color amountColor;
                          Color? tileColor;
                          if (m.movementType == 'increment') {
                            amountColor = Colors.green.shade700;
                            tileColor = Colors.green.shade50;
                          } else if (m.movementType == 'reduction') {
                            amountColor = Colors.red.shade700;
                            tileColor = Colors.red.shade50;
                          } else {
                            // inicial
                            amountColor = Colors.blue.shade700;
                            tileColor = Colors.blue.shade50;
                          }

                          return ListTile(
                            tileColor: tileColor,
                            title: Text(
                              tipo,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: amountColor,
                              ),
                            ),
                            subtitle: Text(_formatDate(m.createdAt)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '\$${_formatAmount(m.amount)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: amountColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      _editMovement(m);
                                    } else if (value == 'delete') {
                                      _confirmDeleteMovement(m);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit, size: 20),
                                          SizedBox(width: 8),
                                          Text('Editar'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete,
                                              size: 20, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Eliminar',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
          ]),
        ),
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
