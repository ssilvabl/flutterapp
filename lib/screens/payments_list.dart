import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_messages.dart';
import '../utils/session_manager.dart';
import '../utils/interface_labels.dart';
import '../utils/preference_provider.dart';
import '../constants/user_roles.dart';
import 'login.dart';
import 'payment_details.dart';
import 'profile.dart';
import 'admin.dart';
import 'statistics.dart';
import 'subscription.dart';

class PaymentsListPage extends StatefulWidget {
  const PaymentsListPage({super.key});

  @override
  State<PaymentsListPage> createState() => _PaymentsListPageState();
}

class Payment {
  final String id;
  final String entity;
  final double amount; // Monto inicial
  double currentAmount; // Monto actual calculado desde movimientos
  final DateTime createdAt;
  final DateTime? endDate;
  final String type;
  final String? description;

  Payment(
      {required this.id,
      required this.entity,
      required this.amount,
      required this.currentAmount,
      required this.createdAt,
      this.endDate,
      required this.type,
      this.description});

  factory Payment.fromMap(Map<String, dynamic> m) {
    final amt = (m['amount'] != null)
        ? (double.tryParse(m['amount'].toString()) ?? 0.0)
        : 0.0;
    return Payment(
      id: m['id'].toString(),
      entity: m['entity_name'] ?? '',
      amount: amt,
      currentAmount: amt, // Se actualizará después
      createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
      endDate: m['end_date'] != null
          ? DateTime.tryParse(m['end_date'] is String
              ? m['end_date']
              : m['end_date'].toString())
          : null,
      type: (m['type'] ?? 'cobro').toString(),
      description: m['description'] as String?,
    );
  }
}

class _PaymentsListPageState extends State<PaymentsListPage> {
  final _supabase = Supabase.instance.client;
  List<Payment> _items = [];
  List<Payment> _filteredItems = [];
  bool _loading = false;
  bool _loadingMore = false;
  int _page = 0;
  final int _pageSize = 10;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _filterType = 'all'; // 'all' | 'cobro' | 'pago'
  String _sortOrder =
      'date_desc'; // 'date_desc', 'date_asc', 'alpha', 'amount_desc', 'amount_asc'
  double _totalCobros = 0.0;
  double _totalPagos = 0.0;
  int _totalCount = 0;
  int _totalCountDB = 0; // Conteo total en DB
  bool _hasMoreItems = true;

  StreamSubscription<List<Map<String, dynamic>>>? _paymentsSub;
  StreamSubscription<List<Map<String, dynamic>>>? _movementsSub;
  String? _profileName;
  UserRole _userRole = UserRole.free;
  bool _canAddTransactions = true;
  int _currentTransactionCount = 0;
  int? _maxTransactions;
  Timer? _sessionCheckTimer;

  // Removemos estas variables ya que usaremos el provider
  // InterfacePreference _interfacePreference = InterfacePreference.prestamista;
  // InterfaceLabels get _labels => InterfaceLabels(_interfacePreference);

  @override
  void initState() {
    super.initState();
    // Si no hay usuario, redirigimos al login y limpiamos la pila
    if (Supabase.instance.client.auth.currentUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false);
      });
      return;
    }

    // Cargar datos en paralelo para mejorar rendimiento
    _initializeData();
    _startSessionValidation();
    _setupRealtime(); // Habilitar tiempo real
    _loadSortPreference(); // Cargar preferencia de ordenamiento
  }

  // Inicializar todos los datos en paralelo
  Future<void> _initializeData() async {
    await Future.wait([
      _fetch(),
      _loadProfileAndRole(), // Combinar carga de perfil y rol
      _calculateTotalsFromDB(), // Calcular totales desde la BD
    ]);
  }

  // Cargar perfil y rol en una sola consulta
  Future<void> _loadProfileAndRole() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final res = await _supabase
          .from('profiles')
          .select('company, full_name, role')
          .eq('id', uid)
          .maybeSingle();

      if (res != null) {
        setState(() {
          _profileName = res['company'] ?? res['full_name'];
          final roleStr = res['role'] as String? ?? 'free';
          _userRole = UserRoleExtension.fromString(roleStr);
        });

        // Verificar límite de transacciones
        await _checkTransactionLimit();
      }
    } catch (e) {
      print('Error loading profile and role: $e');
    }
  }

  // Calcular totales desde la base de datos (todos los registros, no solo los cargados)
  Future<void> _calculateTotalsFromDB() async {
    try {
      final uid = _userId;
      if (uid == null) return;

      // Obtener todos los payments del usuario
      final paymentsRes = await _supabase
          .from('payments')
          .select('id, type, amount')
          .eq('user_id', uid);

      if (paymentsRes == null) return;

      final paymentsList = paymentsRes as List;
      if (paymentsList.isEmpty) {
        setState(() {
          _totalCobros = 0.0;
          _totalPagos = 0.0;
        });
        return;
      }

      // Obtener todos los movimientos
      final movementsRes = await _supabase
          .from('payments_movements')
          .select('payment_id, movement_type, amount')
          .eq('user_id', uid);

      final movementsList = (movementsRes as List?) ?? [];

      // Agrupar movimientos por payment_id
      final movementsByPayment = <String, List<Map<String, dynamic>>>{};
      for (var mov in movementsList) {
        final paymentId = mov['payment_id'].toString();
        movementsByPayment.putIfAbsent(paymentId, () => []);
        movementsByPayment[paymentId]!.add(mov as Map<String, dynamic>);
      }

      double totalCobros = 0.0;
      double totalPagos = 0.0;

      // Calcular currentAmount para cada payment y sumar por tipo
      for (var payment in paymentsList) {
        final paymentMap = payment as Map<String, dynamic>;
        final paymentId = paymentMap['id'].toString();
        final type = paymentMap['type'] as String;
        final initialAmount = (paymentMap['amount'] as num?)?.toDouble() ?? 0.0;

        // Calcular currentAmount basado en movimientos
        final movements = movementsByPayment[paymentId] ?? [];
        double initial = 0.0;
        double increments = 0.0;
        double reductions = 0.0;

        for (var mov in movements) {
          final movType = mov['movement_type'] as String;
          final amount = (mov['amount'] as num?)?.toDouble() ?? 0.0;

          if (movType == 'initial') {
            initial += amount;
          } else if (movType == 'increment') {
            increments += amount;
          } else if (movType == 'reduction') {
            reductions += amount;
          }
        }

        double currentAmount = initial + increments - reductions;

        // Si no hay movimientos, usar el amount inicial
        if (initial == 0.0 && increments == 0.0 && reductions == 0.0) {
          currentAmount = initialAmount;
        }

        // Sumar al total correspondiente
        if (type == 'cobro') {
          totalCobros += currentAmount;
        } else if (type == 'pago') {
          totalPagos += currentAmount;
        }
      }

      setState(() {
        _totalCobros = totalCobros;
        _totalPagos = totalPagos;
      });
    } catch (e) {
      print('Error calculating totals from DB: $e');
    }
  }

  // Setup tiempo real para payments y movements
  void _setupRealtime() {
    final uid = _userId;
    if (uid == null) return;

    // Suscribirse a cambios en payments
    _paymentsSub = _supabase
        .from('payments')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen((data) async {
          if (!mounted) return;
          print('🔄 Actualización en tiempo real: ${data.length} registros');

          // Convertir datos recibidos
          final newPayments = data.map((e) => Payment.fromMap(e)).toList();
          
          // Actualizar solo los items que ya tenemos cargados (mantener paginación)
          final updatedItems = <Payment>[];
          bool hasChanges = false;
          
          for (final item in _items) {
            final updated = newPayments.firstWhere(
              (p) => p.id == item.id,
              orElse: () => item,
            );
            
            // Verificar si cambió
            if (updated.entity != item.entity || 
                updated.amount != item.amount ||
                updated.type != item.type) {
              hasChanges = true;
            }
            
            updatedItems.add(updated);
          }
          
          // Solo actualizar si hubo cambios reales
          if (hasChanges) {
            // Calcular montos actuales
            await _calculateCurrentAmounts(updatedItems);

            setState(() {
              _items = updatedItems;
            });
            _applyFilter();
          }
          
          // SIEMPRE recalcular totales desde la BD (incluye todos los registros)
          await _calculateTotalsFromDB();
        });

    // Suscribirse a cambios en movements para actualizar montos
    _movementsSub = _supabase
        .from('payments_movements')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen((data) async {
          if (!mounted) return;
          print('📊 Actualización de movimientos en tiempo real');

          // Recalcular montos actuales de los pagos cargados
          await _calculateCurrentAmounts(_items);
          setState(() {});
          _applyFilter();
          // Recalcular totales desde la BD (todos los registros)
          await _calculateTotalsFromDB();
        });
  }

  // Calcular montos actuales basados en movimientos
  Future<void> _calculateCurrentAmounts(List<Payment> payments) async {
    for (final payment in payments) {
      try {
        final movesRes = await _supabase
            .from('payments_movements')
            .select()
            .eq('payment_id', payment.id)
            .order('created_at', ascending: true);

        final List<Map<String, dynamic>> movesData =
            (movesRes is List) ? List<Map<String, dynamic>>.from(movesRes) : [];

        double initial = 0.0;
        double increments = 0.0;
        double reductions = 0.0;

        for (final move in movesData) {
          final type = move['movement_type'] as String? ?? '';
          final amount = (move['amount'] != null)
              ? (double.tryParse(move['amount'].toString()) ?? 0.0)
              : 0.0;

          if (type == 'initial') {
            initial += amount;
          } else if (type == 'increment') {
            increments += amount;
          } else if (type == 'reduction') {
            reductions += amount;
          }
        }

        // Si no hay movimientos initial será 0, entonces usamos amount como fallback
        if (initial == 0.0 && increments == 0.0 && reductions == 0.0) {
          payment.currentAmount = payment.amount;
        } else {
          payment.currentAmount = initial + increments - reductions;
        }
      } catch (e) {
        print('Error calculando monto actual para ${payment.id}: $e');
        payment.currentAmount = payment.amount;
      }
    }
  }

  Future<void> _loadProfile() async {
    // Mantener por compatibilidad, pero ahora llama a la versión combinada
    await _loadProfileAndRole();
  }

  Future<void> _loadUserRole() async {
    // Mantener por compatibilidad, pero ahora llama a la versión combinada
    await _loadProfileAndRole();
  }

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> _fetch({bool next = false}) async {
    if (next) {
      if (_loadingMore || !_hasMoreItems) return;
      setState(() => _loadingMore = true);
      _page++;
    } else {
      _page = 0;
      setState(() => _loading = true);
    }

    final from = _page * _pageSize;
    try {
      if (_userId == null) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
        return;
      }

      // Obtener conteo total primero
      if (!next) {
        try {
          final countRes = await _supabase
              .from('payments')
              .select('id', const FetchOptions(count: CountOption.exact))
              .eq('user_id', _userId);
          _totalCountDB = countRes.count ?? 0;
        } catch (e) {
          print('Error obteniendo conteo: $e');
          _totalCountDB = 0;
        }
      }

      // Obtener registros paginados con ordenamiento según preferencia
      var query = _supabase
          .from('payments')
          .select()
          .eq('user_id', _userId);
      
      // Aplicar ordenamiento del servidor
      query = _applySortOrderToQuery(query);
      
      final res = await query.range(from, from + _pageSize - 1);

      final List<Map<String, dynamic>> data = (res is List)
          ? List<Map<String, dynamic>>.from(res)
          : <Map<String, dynamic>>[];
      final items = data.map((e) => Payment.fromMap(e)).toList();

      // Calcular montos actuales
      await _calculateCurrentAmounts(items);

      // Detectar si hay más items disponibles
      _hasMoreItems = items.length >= _pageSize;

      if (next) {
        // Append only items that are not already present to avoid duplicates
        final existingIds = _items.map((e) => e.id).toSet();
        final newItems =
            items.where((it) => !existingIds.contains(it.id)).toList();
        setState(() => _items = [..._items, ...newItems]);
      } else {
        // Replace on fresh load
        setState(() => _items = items);
      }

      // Aplicar filtros después de actualizar items
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo cargar los pagos');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    _paymentsSub?.cancel();
    _movementsSub?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Cargar preferencia de ordenamiento
  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sortOrder = prefs.getString('sort_order') ?? 'date_desc';
    });
  }

  // Guardar preferencia de ordenamiento
  Future<void> _saveSortPreference(String order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sort_order', order);
    setState(() {
      _sortOrder = order;
    });
    _applyFilter();
  }

  Future<void> _checkTransactionLimit() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;

      final roleStr = _userRole.toString().split('.').last;
      final limitResult =
          await SessionManager.checkTransactionLimit(uid, roleStr);

      setState(() {
        _canAddTransactions = limitResult.canAdd;
        _currentTransactionCount = limitResult.currentCount;
        _maxTransactions = limitResult.maxCount;
      });
    } catch (e) {
      print('Error checking transaction limit: $e');
    }
  }

  /// Inicia la verificación periódica de validez de sesión
  void _startSessionValidation() {
    // Verificar cada 60 segundos (optimizado para mejor rendimiento)
    _sessionCheckTimer =
        Timer.periodic(const Duration(seconds: 60), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final isValid = await SessionManager.isSessionValid();
      if (!isValid) {
        // La sesión fue eliminada desde otro dispositivo
        timer.cancel();
        await _handleSessionInvalidated();
      }
    });
  }

  /// Maneja cuando la sesión ha sido invalidada desde otro dispositivo
  Future<void> _handleSessionInvalidated() async {
    // Cerrar sesión localmente
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    // Mostrar mensaje y redirigir al login
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tu sesión ha sido cerrada desde otro dispositivo'),
        duration: Duration(seconds: 5),
      ),
    );
  }

  Future<void> _delete(String id) async {
    setState(() => _loading = true);
    try {
      if (_userId == null) throw Exception('No autorizado');
      await _supabase
          .from('payments')
          .delete()
          .eq('id', id)
          .eq('user_id', _userId);
      setState(() => _items.removeWhere((i) => i.id == id));
      _applyFilter();

      // Actualizar el límite de transacciones después de eliminar
      await _checkTransactionLimit();
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e, fallback: 'No se pudo eliminar');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final ok = await _confirm(
        'Cerrar sesión', '¿Estás seguro que deseas cerrar sesión?');
    if (ok != true) return;
    setState(() => _loading = true);

    // Eliminar la sesión actual antes de cerrar sesión
    await SessionManager.removeCurrentSession();

    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()), (route) => false);
  }

  Future<void> _showEditDialog({Payment? p}) async {
    // Obtener labels del provider
    final preferenceProvider = PreferenceInheritedWidget.of(context);
    final labels = preferenceProvider?.labels ??
        InterfaceLabels(InterfacePreference.prestamista);
    final entityCtrl = TextEditingController(text: p?.entity ?? '');
    // For creation: amountCtrl = absolute amount; for edit: amountCtrl = delta to apply
    final amountCtrl = TextEditingController(text: p == null ? '' : '');
    final descriptionCtrl = TextEditingController(text: p?.description ?? '');
    final endDateCtrl = TextEditingController(
        text: p != null && p.endDate != null ? _formatDate(p.endDate!) : '');
    DateTime? endDate = p?.endDate;
    String type = p?.type ?? 'cobro';
    final formKey = GlobalKey<FormState>();

    double delta = 0.0;
    String? previewOp; // 'increment' or 'reduction'
    double previewFinal = p?.currentAmount ?? 0.0;
    bool hasChanges = false;

    // Función para detectar cambios
    void checkForChanges() {
      if (p == null) {
        // Creación: verificar si hay datos
        hasChanges = entityCtrl.text.trim().isNotEmpty ||
            amountCtrl.text.trim().isNotEmpty ||
            descriptionCtrl.text.trim().isNotEmpty;
      } else {
        // Edición: verificar si algo cambió
        hasChanges = entityCtrl.text.trim() != (p.entity) ||
            type != (p.type) ||
            descriptionCtrl.text.trim() != (p.description ?? '') ||
            (endDate?.toString() != p.endDate?.toString()) ||
            previewOp != null;
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: Text(p == null
              ? (type == 'cobro'
                  ? 'Agregar ${labels.cobro}'
                  : 'Agregar ${labels.pago}')
              : (type == 'cobro'
                  ? 'Editar ${labels.cobro}'
                  : 'Editar ${labels.pago}')),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: entityCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Nombre de la Entidad/Persona'),
                    onChanged: (v) {
                      checkForChanges();
                      setStateDialog(() {});
                    },
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
                  ),
                  const SizedBox(height: 8),
                  if (p != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Monto Actual: \$${_formatAmount(p.currentAmount)}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        const Text(
                            'Puedes editar el nombre, tipo o descripción sin cambiar el monto. Si deseas modificar el monto, ingresa el valor a ajustar y presiona "Incrementar" o "Reducir".',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 6),
                      ],
                    ),
                  TextFormField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                        labelText: p == null
                            ? 'Monto Inicial'
                            : 'Monto a ajustar (opcional)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      _formatCurrencyController(amountCtrl, v);
                      delta = _parseAmountFromFormatted(amountCtrl.text);
                      // reset preview operation until user chooses increment/reduce
                      previewOp = null;
                      previewFinal = p?.currentAmount ?? 0.0;
                      checkForChanges();
                      setStateDialog(() {});
                    },
                    validator: (v) {
                      // Solo validar si es creación (p == null)
                      if (p == null) {
                        return (v == null || _parseAmountFromFormatted(v) <= 0)
                            ? 'Monto inválido'
                            : null;
                      }
                      // Para edición, es opcional
                      return null;
                    },
                  ),
                  if (p != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                                onPressed: () {
                                  final val = _parseAmountFromFormatted(
                                      amountCtrl.text);
                                  if (val <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Ingresa un monto válido mayor a 0')));
                                    return;
                                  }
                                  previewOp = 'increment';
                                  delta = val;
                                  previewFinal = p.currentAmount + delta;
                                  checkForChanges();
                                  setStateDialog(() {});
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Incrementar')),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                                onPressed: () {
                                  final val = _parseAmountFromFormatted(
                                      amountCtrl.text);
                                  if (val <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Ingresa un monto válido mayor a 0')));
                                    return;
                                  }
                                  previewOp = 'reduction';
                                  delta = val;
                                  previewFinal = p.currentAmount - delta;
                                  if (previewFinal < 0) previewFinal = 0.0;
                                  checkForChanges();
                                  setStateDialog(() {});
                                },
                                icon: const Icon(Icons.remove),
                                label: const Text('Reducir')),
                          ),
                        ],
                      ),
                    ),
                  if (p != null && previewOp != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              'Vista previa: ${previewOp == 'increment' ? '+' : '-'}\$${_formatAmount(delta)}'),
                          const SizedBox(height: 4),
                          Text('Nuevo monto: \$${_formatAmount(previewFinal)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: type,
                    items: [
                      DropdownMenuItem(
                          value: 'cobro', child: Text(labels.cobro)),
                      DropdownMenuItem(value: 'pago', child: Text(labels.pago)),
                    ],
                    onChanged: (v) {
                      type = v ?? 'cobro';
                      checkForChanges();
                      setStateDialog(() {});
                    },
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                    maxLines: 3,
                    onChanged: (v) {
                      checkForChanges();
                      setStateDialog(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: endDateCtrl,
                    readOnly: true,
                    decoration: const InputDecoration(
                        labelText: 'Fecha Fin (Opcional)'),
                    onTap: () async {
                      final picked = await showDatePicker(
                          context: context,
                          locale: const Locale('es', 'ES'),
                          initialDate: endDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100));
                      if (picked != null) {
                        endDate = picked;
                        endDateCtrl.text = _formatDate(picked);
                        checkForChanges();
                        setStateDialog(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: hasChanges
                  ? () async {
                      if (!formKey.currentState!.validate()) return;
                      final entity = entityCtrl.text.trim();
                      final description = descriptionCtrl.text.trim();

                      if (p == null) {
                        // creation: amountCtrl holds absolute amount
                        final amount =
                            _parseAmountFromFormatted(amountCtrl.text);
                        Navigator.of(context).pop(true);
                        await _create(
                            entity, amount, endDate, type, description);
                        return;
                      }

                      // edit: if there's a preview operation, create the movement first
                      if (previewOp != null && delta > 0) {
                        try {
                          await _supabase.from('payments_movements').insert({
                            'payment_id': p.id,
                            'user_id': _userId,
                            'movement_type': previewOp == 'increment'
                                ? 'increment'
                                : 'reduction',
                            'amount': delta,
                            'note': previewOp == 'increment'
                                ? 'Incremento manual'
                                : 'Reducción manual',
                            'created_at': DateTime.now().toIso8601String(),
                          });
                        } catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('Error al guardar el movimiento: $e')));
                          return;
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.of(context).pop(true);
                      await _update(p.id, entity, endDate, type, description);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: hasChanges ? null : Colors.grey,
              ),
              child: const Text('Guardar'),
            ),
          ],
        );
      }),
    );

    if (result == true) {
      // Recargar desde el inicio para mostrar el cambio
      _page = 0;
      _items.clear();
      await _fetch();

      // Actualizar el límite de transacciones después de agregar/editar
      await _checkTransactionLimit();
    }
  }

  Future<void> _create(String entity, double amount, DateTime? endDate,
      String type, String description) async {
    setState(() => _loading = true);
    try {
      if (_userId == null) throw Exception('No autorizado');
      final now = DateTime.now();
      final res = await _supabase.from('payments').insert({
        'entity_name': entity,
        'amount': amount,
        'user_id': _userId,
        'end_date': endDate?.toIso8601String(),
        'type': type,
        'description': description,
        'created_at': now.toIso8601String(),
      }).select();

      // If insertion succeeded, create an initial movement record
      if ((res as List).isNotEmpty) {
        final created = res[0] as Map<String, dynamic>;
        final pid = created['id']?.toString();
        if (pid != null) {
          await _supabase.from('payments_movements').insert({
            'payment_id': pid,
            'user_id': _userId,
            'movement_type': 'initial',
            'amount': amount,
            'note': 'Monto inicial',
            'created_at': now.toIso8601String(),
          });
        }
      }

      if (mounted) {
        final labels = PreferenceInheritedWidget.watch(context).labels;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(type == 'cobro'
                ? '${labels.cobro} agregado'
                : '${labels.pago} agregado')));
        
        // Recalcular totales inmediatamente
        await _calculateTotalsFromDB();
      }
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo agregar el pago');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update(String id, String entity, DateTime? endDate, String type,
      String description) async {
    setState(() => _loading = true);
    try {
      if (_userId == null) throw Exception('No autorizado');

      // Update only descriptive fields, never modify the amount
      await _supabase
          .from('payments')
          .update({
            'entity_name': entity,
            'end_date': endDate?.toIso8601String(),
            'type': type,
            'description': description,
          })
          .eq('id', id)
          .eq('user_id', _userId);

      if (mounted) {
        final labels = PreferenceInheritedWidget.watch(context).labels;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(type == 'cobro'
                ? '${labels.cobro} actualizado'
                : '${labels.pago} actualizado')));
        
        // Recalcular totales inmediatamente
        await _calculateTotalsFromDB();
      }
    } catch (e) {
      if (!mounted) return;
      final msg =
          friendlySupabaseMessage(e, fallback: 'No se pudo actualizar el pago');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Obtener labels del provider
    final preferenceProvider = PreferenceInheritedWidget.watch(context);
    final labels = preferenceProvider.labels;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lista de ${labels.pagos} / ${labels.cobros}'),
        automaticallyImplyLeading: true,
        actions: [
          if (_profileName != null && _profileName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Center(
                  child: Text(
                    _profileName!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            const DrawerHeader(
                decoration: BoxDecoration(color: Colors.black87),
                child: Center(
                    child:
                        Text('Menú', style: TextStyle(color: Colors.white)))),
            ListTile(
                leading: const Icon(Icons.person),
                title: const Text('Perfil'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfilePage()));
                }),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Estadísticas'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StatisticsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.card_membership),
              title: const Text('Suscripción'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubscriptionPage()),
                );
              },
            ),
            if (_userRole == UserRole.admin)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: const Text('Administración'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AdminPage()),
                  );
                },
              ),
            const Spacer(),
            ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Cerrar sesión'),
                onTap: _logout),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              return _buildTopControls(wide, constraints.maxWidth, labels);
            }),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _fetch();
                  _applyFilter();
                },
                child: _filteredItems.isEmpty && !_loading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          Center(child: Text('Sin registros')),
                        ],
                      )
                    : Column(
                        children: [
                          Expanded(
                            child: ListView.separated(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _filteredItems.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final it = _filteredItems[index];
                                final screenWidth =
                                    MediaQuery.of(context).size.width;
                                final showPopupActions = screenWidth < 600;

                                return GestureDetector(
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => PaymentDetailsPage(
                                          payment: {
                                            'id': it.id,
                                            'entity': it.entity,
                                            'amount': it.currentAmount,
                                            'createdAt': it.createdAt,
                                            'endDate': it.endDate,
                                            'type': it.type,
                                            'description': it.description,
                                          },
                                          onEdit: (payment) async {
                                            await _showEditDialog(p: payment);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  child: Row(
                                    children: [
                                      // Número de registro
                                      Container(
                                        width: 40,
                                        height: 40,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: it.type == 'cobro'
                                              ? Colors.green.withOpacity(0.2)
                                              : Colors.red.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                            color: it.type == 'cobro'
                                                ? Colors.green
                                                : Colors.red,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '#${index + 1}',
                                            style: TextStyle(
                                              color: it.type == 'cobro'
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 16),
                                          decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius:
                                                  BorderRadius.circular(10)),
                                          child:
                                              LayoutBuilder(builder: (ctx, c) {
                                            final narrow = c.maxWidth < 520;
                                            if (narrow) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          it.entity,
                                                          style:
                                                              const TextStyle(
                                                                  color: Colors
                                                                      .white),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      ConstrainedBox(
                                                          constraints:
                                                              const BoxConstraints(
                                                                  minWidth: 60),
                                                          child: Text(
                                                              '\$${_formatAmount(it.currentAmount)}',
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white),
                                                              textAlign:
                                                                  TextAlign
                                                                      .right)),
                                                    ],
                                                  ),
                                                  if (it.endDate != null) ...[
                                                    const SizedBox(height: 6),
                                                    Text(
                                                        'Vence: ${_formatDate(it.endDate!)}',
                                                        style: const TextStyle(
                                                            color:
                                                                Colors.white70,
                                                            fontSize: 12),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                  ],
                                                ],
                                              );
                                            }

                                            // Wide layout: keep items on one row but allow wrapping of text
                                            return Row(
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(it.entity,
                                                                style: const TextStyle(
                                                                    color: Colors
                                                                        .white),
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis),
                                                            if (it.endDate !=
                                                                null)
                                                              Text(
                                                                  'Vence: ${_formatDate(it.endDate!)}',
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white70,
                                                                      fontSize:
                                                                          12),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis),
                                                          ],
                                                        ),
                                                      ),
                                                      ConstrainedBox(
                                                          constraints:
                                                              const BoxConstraints(
                                                                  minWidth: 60),
                                                          child: Text(
                                                              '\$${_formatAmount(it.currentAmount)}',
                                                              style: const TextStyle(
                                                                  color: Colors
                                                                      .white),
                                                              textAlign:
                                                                  TextAlign
                                                                      .right)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          }),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Acciones externas: popup en chico, fila completa en ancho
                                      showPopupActions
                                          ? PopupMenuButton<String>(
                                              onSelected: (v) async {
                                                if (v == 'delete') {
                                                  await _confirmDelete(it.id);
                                                  return;
                                                }
                                                if (v == 'edit') {
                                                  await _showEditDialog(p: it);
                                                  return;
                                                }
                                                if (v == 'details') {
                                                  await Navigator.of(context)
                                                      .push(MaterialPageRoute(
                                                          builder: (_) =>
                                                              PaymentDetailsPage(
                                                                  payment: {
                                                                    'id': it.id,
                                                                    'entity': it
                                                                        .entity,
                                                                    'amount': it
                                                                        .currentAmount,
                                                                    'createdAt':
                                                                        it.createdAt,
                                                                    'endDate': it
                                                                        .endDate,
                                                                    'type':
                                                                        it.type,
                                                                    'description':
                                                                        it.description,
                                                                  },
                                                                  onEdit:
                                                                      (payment) async {
                                                                    await _showEditDialog(
                                                                        p: payment);
                                                                  })));
                                                  return;
                                                }
                                              },
                                              itemBuilder: (_) => const [
                                                PopupMenuItem(
                                                    value: 'details',
                                                    child: Text('Detalles')),
                                                PopupMenuItem(
                                                    value: 'edit',
                                                    child: Text('Editar')),
                                                PopupMenuItem(
                                                    value: 'delete',
                                                    child: Text('Eliminar',
                                                        style: TextStyle(
                                                            color:
                                                                Colors.red))),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.delete_outline,
                                                      color: Colors.red,
                                                      size: 32),
                                                  onPressed: () =>
                                                      _confirmDelete(it.id),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.edit_outlined,
                                                      color: Colors.black,
                                                      size: 28),
                                                  onPressed: () =>
                                                      _showEditDialog(p: it),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                      Icons.info_outline,
                                                      color: Colors.blue,
                                                      size: 28),
                                                  tooltip: 'Detalles',
                                                  onPressed: () async {
                                                    await Navigator.of(context)
                                                        .push(MaterialPageRoute(
                                                            builder: (_) =>
                                                                PaymentDetailsPage(
                                                                    payment: {
                                                                      'id':
                                                                          it.id,
                                                                      'entity':
                                                                          it.entity,
                                                                      'amount':
                                                                          it.currentAmount,
                                                                      'createdAt':
                                                                          it.createdAt,
                                                                      'endDate':
                                                                          it.endDate,
                                                                      'type': it
                                                                          .type,
                                                                      'description':
                                                                          it.description,
                                                                    },
                                                                    onEdit:
                                                                        (payment) async {
                                                                      await _showEditDialog(
                                                                          p: payment);
                                                                    })));
                                                  },
                                                ),
                                              ],
                                            ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          // Botón Ver más
                          if (_hasMoreItems && !_loading)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : ElevatedButton.icon(
                                        onPressed: () => _fetch(next: true),
                                        icon: const Icon(Icons.expand_more),
                                        label: const Text('Ver más'),
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (_loading && _page == 0) const CircularProgressIndicator(),
            const SizedBox(height: 12)
          ],
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

  void _formatCurrencyController(TextEditingController ctrl, String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = digits.isEmpty ? '' : _formatDigitsWithDots(digits);
    ctrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length));
  }

  String _formatDigitsWithDots(String digits) {
    final buffer = StringBuffer();
    int count = 0;
    for (int i = digits.length - 1; i >= 0; i--) {
      buffer.write(digits[i]);
      count++;
      if (count == 3 && i != 0) {
        buffer.write('.');
        count = 0;
      }
    }
    return buffer.toString().split('').reversed.join();
  }

  double _parseAmountFromFormatted(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0.0;
    return double.parse(digits);
  }

  Future<void> _applyFilter() async {
    final q = _searchController.text.trim();

    // If there's a search query, perform server-side search with ordering
    if (q.isNotEmpty) {
      try {
        if (_userId == null) return;
        setState(() => _loading = true);
        final escaped = q.replaceAll('%', '\\%');
        
        // Build query with ordering from server
        var query = _supabase
            .from('payments')
            .select()
            .or("entity_name.ilike.%$escaped%,description.ilike.%$escaped%")
            .eq('user_id', _userId);
        
        // Apply server-side ordering for better performance
        query = _applySortOrderToQuery(query);
        
        final res = await query;
        final List<Map<String, dynamic>> data = (res is List)
            ? List<Map<String, dynamic>>.from(res)
            : <Map<String, dynamic>>[];
        _filteredItems = data.map((e) => Payment.fromMap(e)).toList();
        await _calculateCurrentAmounts(_filteredItems);
      } catch (e) {
        if (!mounted) return;
        final msg = friendlySupabaseMessage(e, fallback: 'Error al buscar');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        return;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      _filteredItems = [..._items];
    }

    // Apply type filter
    if (_filterType != 'all') {
      _filteredItems =
          _filteredItems.where((p) => p.type == _filterType).toList();
    }

    // Apply sort order (client-side for loaded items)
    switch (_sortOrder) {
      case 'date_desc':
        _filteredItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'date_asc':
        _filteredItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'alpha':
        _filteredItems.sort(
            (a, b) => a.entity.toLowerCase().compareTo(b.entity.toLowerCase()));
        break;
      case 'amount_desc':
        _filteredItems
            .sort((a, b) => b.currentAmount.compareTo(a.currentAmount));
        break;
      case 'amount_asc':
        _filteredItems
            .sort((a, b) => a.currentAmount.compareTo(b.currentAmount));
        break;
    }

    // Los totales se calculan desde la BD en _calculateTotalsFromDB (todos los registros)
    _totalCount = _filteredItems.length;

    if (mounted) setState(() {});
  }

  // Helper para aplicar ordenamiento en consultas al servidor
  dynamic _applySortOrderToQuery(dynamic query) {
    switch (_sortOrder) {
      case 'date_desc':
        return query.order('created_at', ascending: false);
      case 'date_asc':
        return query.order('created_at', ascending: true);
      case 'alpha':
        return query.order('entity_name', ascending: true);
      case 'amount_desc':
        return query.order('amount', ascending: false);
      case 'amount_asc':
        return query.order('amount', ascending: true);
      default:
        return query.order('created_at', ascending: false);
    }
  }

  Widget _buildTopControls(bool wide, double maxWidth, InterfaceLabels labels) {
    if (wide) {
      return Column(
        children: [
          // Primera fila: Buscador y botón de agregar
          Row(
            children: [
              // Search bar
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    _applyFilter();
                  },
                ),
              ),
              const SizedBox(width: 12),

              // Add button - with transaction limit check
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _canAddTransactions ? () => _showEditDialog() : null,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _canAddTransactions
                          ? const LinearGradient(
                              colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                            )
                          : null,
                      color: _canAddTransactions ? null : Colors.grey,
                    ),
                    child: const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Segunda fila: Chips de filtro y totales
          Row(
            children: [
              // Filter chips (Todos / Cobros / Pagos)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildFilterChip('Todos', 'all'),
                    const SizedBox(width: 4),
                    _buildFilterChip(labels.cobros, 'cobro',
                        color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    _buildFilterChip(labels.pagos, 'pago',
                        color: Colors.grey[800]),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Totales en tarjetas destacadas
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _buildModernTotalCard(
                        'Total ${labels.cobros.toLowerCase()}',
                        _totalCobros,
                        Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildModernTotalCard(
                        'Total ${labels.pagos.toLowerCase()}',
                        _totalPagos,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Sort button
              IconButton(
                icon: const Icon(Icons.sort, size: 24),
                tooltip: 'Ordenar',
                onPressed: () => _showSortDialog(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Contador de registros
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Registros: $_totalCount${_totalCountDB > 0 ? ' de $_totalCountDB' : ''}',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ),
        ],
      );
    }

    // Narrow layout: vertical stacking
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Buscador y botón agregar
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  isDense: true,
                ),
                onChanged: (v) => _applyFilter(),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _canAddTransactions ? () => _showEditDialog() : null,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _canAddTransactions
                        ? const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          )
                        : null,
                    color: _canAddTransactions ? null : Colors.grey,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Chips de filtro
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(child: _buildFilterChip('Todos', 'all')),
                    const SizedBox(width: 4),
                    Expanded(
                        child: _buildFilterChip(labels.cobros, 'cobro',
                            color: Colors.amber[700])),
                    const SizedBox(width: 4),
                    Expanded(
                        child: _buildFilterChip(labels.pagos, 'pago',
                            color: Colors.grey[800])),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.sort, size: 24),
              tooltip: 'Ordenar',
              onPressed: () => _showSortDialog(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.grey[100],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Tarjetas de totales
        Row(
          children: [
            Expanded(
              child: _buildModernTotalCard(
                'Total ${labels.cobros.toLowerCase()}',
                _totalCobros,
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildModernTotalCard(
                'Total ${labels.pagos.toLowerCase()}',
                _totalPagos,
                Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Registros: $_totalCount${_totalCountDB > 0 ? ' de $_totalCountDB' : ''}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String filterType, {Color? color}) {
    final isSelected = _filterType == filterType;
    // Si no tiene color personalizado (como "Todos"), usar azul oscuro
    final backgroundColor =
        isSelected ? (color ?? const Color(0xFF1976D2)) : Colors.transparent;

    return GestureDetector(
      onTap: () {
        setState(() => _filterType = filterType);
        _applyFilter();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildModernTotalCard(String title, double value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${_formatAmount(value)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _showSortDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ordenar por'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<String>(
              title: const Text('Fecha (más reciente primero)'),
              value: 'date_desc',
              groupValue: _sortOrder,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
            RadioListTile<String>(
              title: const Text('Fecha (más antiguo primero)'),
              value: 'date_asc',
              groupValue: _sortOrder,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
            RadioListTile<String>(
              title: const Text('Alfabético (A-Z)'),
              value: 'alpha',
              groupValue: _sortOrder,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
            RadioListTile<String>(
              title: const Text('Monto (mayor a menor)'),
              value: 'amount_desc',
              groupValue: _sortOrder,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
            RadioListTile<String>(
              title: const Text('Monto (menor a mayor)'),
              value: 'amount_asc',
              groupValue: _sortOrder,
              onChanged: (v) => Navigator.of(context).pop(v),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await _saveSortPreference(result);
    }
  }

  Future<void> _shareInvoice(Payment p) async {
    try {
      setState(() => _loading = true);

      // Try to fetch movements by payment_id (string); if none found, try numeric id
      List<dynamic> movesData = [];
      try {
        final res = await _supabase
            .from('payments_movements')
            .select()
            .eq('payment_id', p.id)
            .order('created_at', ascending: false);
        movesData = (res as List<dynamic>? ?? []);
      } catch (_) {
        movesData = [];
      }

      if (movesData.isEmpty) {
        // Attempt to parse numeric id and retry
        try {
          final nid = int.tryParse(p.id);
          if (nid != null) {
            final res2 = await _supabase
                .from('payments_movements')
                .select()
                .eq('payment_id', nid)
                .order('created_at', ascending: true);
            movesData = (res2 as List<dynamic>? ?? []);
          }
        } catch (_) {
          // ignore
        }
      }

      final List<Map<String, dynamic>> movesDataList =
          List<Map<String, dynamic>>.from(movesData);
      final moves = movesDataList.map((e) => Movement.fromMap(e)).toList();

      // Calculate totals
      final initial = moves
          .where((m) => m.movementType == 'initial')
          .fold(0.0, (s, m) => s + m.amount);
      final increments = moves
          .where((m) => m.movementType == 'increment')
          .fold(0.0, (s, m) => s + m.amount);
      final reductions = moves
          .where((m) => m.movementType == 'reduction')
          .fold(0.0, (s, m) => s + m.amount);

      // Calcular el monto actual real basado en los movimientos
      final amountVal = initial + increments - reductions;

      final doc = pw.Document();
      final profile = _profileName ?? '';

      doc.addPage(pw.MultiPage(
        build: (pw.Context ctx) {
          final content = <pw.Widget>[];
          content.add(pw.Header(
              level: 0,
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (profile.isNotEmpty)
                      pw.Text(profile, style: const pw.TextStyle(fontSize: 18)),
                    pw.Text('Factura - ${p.entity}',
                        style: const pw.TextStyle(fontSize: 16)),
                  ])));

          content.add(pw.SizedBox(height: 6));
          content.add(pw.Paragraph(
              text: 'Monto Actual: \$${amountVal.toStringAsFixed(0)}'));
          content.add(pw.SizedBox(height: 10));

          if (moves.isEmpty) {
            content.add(pw.Paragraph(text: 'Sin movimientos registrados'));
          } else {
            content.add(pw.TableHelper.fromTextArray(
              context: ctx,
              headers: ['Fecha', 'Tipo', 'Valor'],
              data: moves.map((m) {
                final tipo = m.movementType == 'initial'
                    ? 'Inicial'
                    : m.movementType == 'increment'
                        ? 'Incremento'
                        : m.movementType == 'reduction'
                            ? 'Reducción'
                            : m.movementType;
                return [
                  m.createdAt.toIso8601String().substring(0, 10),
                  tipo,
                  '\$${_formatAmount(m.amount)}'
                ];
              }).toList(),
            ));

            content.add(pw.SizedBox(height: 10));
            content.add(pw.Paragraph(
                text: 'Monto Inicial: \$${_formatAmount(initial)}'));
            content.add(pw.Paragraph(
                text: 'Total Incrementos: \$${_formatAmount(increments)}'));
            content.add(pw.Paragraph(
                text: 'Total Reducciones: \$${_formatAmount(reductions)}'));
            content.add(pw.Paragraph(
                text: 'Monto Final: \$${_formatAmount(amountVal)}'));
          }

          return content;
        },
      ));

      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'factura_${p.id}.pdf');
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e, fallback: 'Error al generar PDF');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _confirm(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirmar')),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(String id) async {
    final ok = await _confirm('Confirmar eliminación',
        '¿Estás seguro que deseas eliminar este pago?');
    if (ok == true) {
      await _delete(id);
    }
  }
}
