import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../utils/error_messages.dart';
import '../utils/preference_provider.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final _supabase = Supabase.instance.client;
  bool _loading = false;
  double _totalCobros = 0.0;
  double _totalPagos = 0.0;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  // Removemos estas variables ya que usaremos el provider
  // InterfacePreference _interfacePreference = InterfacePreference.prestamista;
  // InterfaceLabels get _labels => InterfaceLabels(_interfacePreference);

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Formatear fechas para la consulta
      final startDateStr = _startDate.toIso8601String();
      final endDateStr = _endDate.toIso8601String();

      // Obtener pagos en el rango de fechas
      final paymentsRes = await _supabase
          .from('payments')
          .select('type, amount')
          .eq('user_id', userId)
          .gte('created_at', startDateStr)
          .lte('created_at', endDateStr);

      final payments = List<Map<String, dynamic>>.from(paymentsRes);

      // Calcular totales
      double cobros = 0.0;
      double pagos = 0.0;

      for (final payment in payments) {
        final amount = (payment['amount'] as num).toDouble();
        if (payment['type'] == 'cobro') {
          cobros += amount;
        } else if (payment['type'] == 'pago') {
          pagos += amount;
        }
      }

      setState(() {
        _totalCobros = cobros;
        _totalPagos = pagos;
      });
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'Error al cargar estadísticas');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF1F2323),
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadStatistics();
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return formatter.format(amount);
  }

  String _formatDateRange() {
    final formatter = DateFormat('dd/MM/yyyy');
    return '${formatter.format(_startDate)} - ${formatter.format(_endDate)}';
  }

  @override
  @override
  Widget build(BuildContext context) {
    // Obtener labels del provider
    final preferenceProvider = PreferenceInheritedWidget.watch(context);
    final labels = preferenceProvider.labels;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        backgroundColor: const Color(0xFF1F2323),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'Filtrar por fecha',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rango de fechas seleccionado
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              color: Color(0xFF1F2323)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Período seleccionado',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDateRange(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _selectDateRange,
                            icon: const Icon(Icons.filter_alt, size: 18),
                            label: const Text('Cambiar'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1F2323),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Título del gráfico
                  const Text(
                    'Comparativa de Cobros vs Pagos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gráfico de barras
                  Container(
                    height: 300,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 5,
                        ),
                      ],
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: (_totalCobros > _totalPagos
                                ? _totalCobros
                                : _totalPagos) *
                            1.2,
                        barTouchData: BarTouchData(
                          enabled: true,
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final label = group.x == 0 ? 'Cobros' : 'Pagos';
                              return BarTooltipItem(
                                '$label\n${_formatCurrency(rod.toY)}',
                                const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) {
                                if (value == 0) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(labels.cobros,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  );
                                } else if (value == 1) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Text(labels.pagos,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  );
                                }
                                return const Text('');
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 60,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  '\$${value.toInt()}',
                                  style: const TextStyle(fontSize: 10),
                                );
                              },
                            ),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                toY: _totalCobros,
                                color: Colors.green,
                                width: 40,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                ),
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                toY: _totalPagos,
                                color: Colors.red,
                                width: 40,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Resumen en tarjetas
                  Row(
                    children: [
                      Expanded(
                        child: Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Icon(Icons.arrow_downward,
                                    color: Colors.green, size: 32),
                                const SizedBox(height: 8),
                                const Text(
                                  'Total Cobros',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatCurrency(_totalCobros),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Card(
                          color: Colors.red.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                const Icon(Icons.arrow_upward,
                                    color: Colors.red, size: 32),
                                const SizedBox(height: 8),
                                const Text(
                                  'Total Pagos',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatCurrency(_totalPagos),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Balance
                  Card(
                    color: (_totalCobros - _totalPagos) >= 0
                        ? Colors.blue.shade50
                        : Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Balance',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _formatCurrency(_totalCobros - _totalPagos),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: (_totalCobros - _totalPagos) >= 0
                                  ? Colors.blue.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
