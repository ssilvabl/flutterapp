import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
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
  final double amount;
  final DateTime createdAt;
  final DateTime? endDate;
  final String type;
  final String? description;

  Payment(
      {required this.id,
      required this.entity,
      required this.amount,
      required this.createdAt,
      this.endDate,
      required this.type,
      this.description});

  factory Payment.fromMap(Map<String, dynamic> m) {
    return Payment(
      id: m['id'].toString(),
      entity: m['entity_name'] ?? '',
      amount: (m['amount'] != null)
          ? (double.tryParse(m['amount'].toString()) ?? 0.0)
          : 0.0,
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
  int _page = 0;
  final int _pageSize = 5;

  final TextEditingController _searchController = TextEditingController();
  String _filterType = 'all'; // 'all' | 'cobro' | 'pago'
  double _totalCobros = 0.0;
  double _totalPagos = 0.0;
  int _totalCount = 0;
  bool _hasMoreItems = true;

  StreamSubscription<List<Map<String, dynamic>>>? _paymentsSub;
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
    
    // Nota: Removimos el stream en tiempo real para respetar la paginación.
    // Los datos se actualizarán cuando el usuario agregue/edite/elimine registros
    // o cuando haga pull-to-refresh.
  }
  
  // Inicializar todos los datos en paralelo
  Future<void> _initializeData() async {
    await Future.wait([
      _fetch(),
      _loadProfileAndRole(), // Combinar carga de perfil y rol
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
      _page++;
    } else {
      _page = 0;
    }
    setState(() => _loading = true);
    final from = _page * _pageSize;
    try {
      if (_userId == null) {
        setState(() => _loading = false);
        return;
      }
      final res = await _supabase
          .from('payments')
          .select()
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);
      final List<Map<String, dynamic>> data = (res is List)
          ? List<Map<String, dynamic>>.from(res)
          : <Map<String, dynamic>>[];
      final items = data.map((e) => Payment.fromMap(e)).toList();
      
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sessionCheckTimer?.cancel();
    _paymentsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkTransactionLimit() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      
      final roleStr = _userRole.toString().split('.').last;
      final limitResult = await SessionManager.checkTransactionLimit(uid, roleStr);
      
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
    _sessionCheckTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
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
    final labels = preferenceProvider?.labels ?? InterfaceLabels(InterfacePreference.prestamista);
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
    double previewFinal = p?.amount ?? 0.0;

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setStateDialog) {
        return AlertDialog(
          title: Text(p == null 
            ? (type == 'cobro' ? 'Agregar ${labels.cobro}' : 'Agregar ${labels.pago}')
            : (type == 'cobro' ? 'Editar ${labels.cobro}' : 'Editar ${labels.pago}')),
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
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Ingresa un nombre' : null,
                  ),
                  const SizedBox(height: 8),
                  if (p != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Monto Actual: \$${_formatAmount(p.amount)}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        const Text(
                            'Ingresa el valor a incrementar o disminuir del monto actual, luego presiona "Incrementar" o "Reducir" para ver la vista previa.'),
                        const SizedBox(height: 6),
                      ],
                    ),
                  TextFormField(
                    controller: amountCtrl,
                    decoration: InputDecoration(
                        labelText: p == null
                            ? 'Monto Inicial'
                            : 'Monto a ajustar (ej: 20.000)'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) {
                      _formatCurrencyController(amountCtrl, v);
                      delta = _parseAmountFromFormatted(amountCtrl.text);
                      // reset preview operation until user chooses increment/reduce
                      previewOp = null;
                      previewFinal = p?.amount ?? 0.0;
                      setStateDialog(() {});
                    },
                    validator: (v) =>
                        (v == null || _parseAmountFromFormatted(v) <= 0)
                            ? 'Monto inválido'
                            : null,
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
                                  previewFinal = p.amount + delta;
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
                                  previewFinal = p.amount - delta;
                                  if (previewFinal < 0) previewFinal = 0.0;
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
                      DropdownMenuItem(value: 'cobro', child: Text(labels.cobro)),
                      DropdownMenuItem(value: 'pago', child: Text(labels.pago)),
                    ],
                    onChanged: (v) => type = v ?? 'cobro',
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descriptionCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                    maxLines: 3,
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
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final entity = entityCtrl.text.trim();
                final description = descriptionCtrl.text.trim();

                if (p == null) {
                  // creation: amountCtrl holds absolute amount
                  final amount = _parseAmountFromFormatted(amountCtrl.text);
                  Navigator.of(context).pop(true);
                  await _create(entity, amount, endDate, type, description);
                  return;
                }

                // edit: require a preview operation (increment or reduction)
                if (previewOp == null) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Presiona Incrementar o Reducir para previsualizar antes de guardar')));
                  return;
                }

                final newAmount = previewFinal;
                Navigator.of(context).pop(true);
                await _update(
                    p.id, entity, newAmount, endDate, type, description);
              },
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(type == 'cobro' ? '${labels.cobro} agregado' : '${labels.pago} agregado')));
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

  Future<void> _update(String id, String entity, double amount,
      DateTime? endDate, String type, String description) async {
    setState(() => _loading = true);
    try {
      if (_userId == null) throw Exception('No autorizado');

      // Fetch current payment to detect amount changes
      final curRes = await _supabase
          .from('payments')
          .select()
          .eq('id', id)
          .eq('user_id', _userId)
          .maybeSingle();

      double previousAmount = 0.0;
      if (curRes != null) {
        final map = curRes as Map<String, dynamic>;
        previousAmount = (map['amount'] != null)
            ? double.tryParse(map['amount'].toString()) ?? 0.0
            : 0.0;
      }

      await _supabase
          .from('payments')
          .update({
            'entity_name': entity,
            'amount': amount,
            'end_date': endDate?.toIso8601String(),
            'type': type,
            'description': description,
          })
          .eq('id', id)
          .eq('user_id', _userId);

      // If amount changed, record a movement
      final delta = amount - previousAmount;
      if (delta != 0.0) {
        final movementType = delta > 0 ? 'increment' : 'reduction';
        await _supabase.from('payments_movements').insert({
          'payment_id': id,
          'user_id': _userId,
          'movement_type': movementType,
          'amount': delta.abs(),
          'note': 'Ajuste manual',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        final labels = PreferenceInheritedWidget.watch(context).labels;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(type == 'cobro' ? '${labels.cobro} actualizado' : '${labels.pago} actualizado')));
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
          automaticallyImplyLeading: true),
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
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final it = _filteredItems[index];
                          final screenWidth = MediaQuery.of(context).size.width;
                          final showPopupActions = screenWidth < 600;
                          return Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 16),
                                  decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(10)),
                                  child: LayoutBuilder(builder: (ctx, c) {
                                    final narrow = c.maxWidth < 520;
                                    if (narrow) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () async {
                                                    await Navigator.of(context)
                                                        .push(MaterialPageRoute(
                                                            builder: (_) =>
                                                                PaymentDetailsPage(
                                                                    payment: {
                                                                      'id': it.id,
                                                                      'entity': it.entity,
                                                                      'amount': it.amount,
                                                                      'createdAt':
                                                                          it.createdAt,
                                                                      'endDate':
                                                                          it.endDate,
                                                                      'type': it.type,
                                                                      'description':
                                                                          it.description,
                                                                    },
                                                                    onEdit: (payment) async {
                                                                      await _showEditDialog(p: payment);
                                                                    })));
                                                  },
                                                  child: Text(
                                                    it.entity,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        decoration: TextDecoration.underline),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 60),
                                                  child: Text(
                                                      '\$${_formatAmount(it.amount)}',
                                                      style: const TextStyle(
                                                          color: Colors.white),
                                                      textAlign:
                                                          TextAlign.right)),
                                            ],
                                          ),
                                          if (it.endDate != null) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                                'Vence: ${_formatDate(it.endDate!)}',
                                                style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 12),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
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
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    GestureDetector(
                                                      onTap: () async {
                                                        await Navigator.of(context)
                                                            .push(MaterialPageRoute(
                                                                builder: (_) =>
                                                                    PaymentDetailsPage(
                                                                        payment: {
                                                                          'id': it.id,
                                                                          'entity': it.entity,
                                                                          'amount': it.amount,
                                                                          'createdAt':
                                                                              it.createdAt,
                                                                          'endDate':
                                                                              it.endDate,
                                                                          'type': it.type,
                                                                          'description':
                                                                              it.description,
                                                                        },
                                                                        onEdit: (payment) async {
                                                                          await _showEditDialog(p: payment);
                                                                        })));
                                                      },
                                                      child: Text(it.entity,
                                                          style: const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              decoration: TextDecoration.underline),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                    ),
                                                    if (it.endDate != null)
                                                      Text(
                                                          'Vence: ${_formatDate(it.endDate!)}',
                                                          style:
                                                              const TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 12),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                  ],
                                                ),
                                              ),
                                              ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                          minWidth: 60),
                                                  child: Text(
                                                      '\$${_formatAmount(it.amount)}',
                                                      style: const TextStyle(
                                                          color: Colors.white),
                                                      textAlign:
                                                          TextAlign.right)),
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
                                          await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      PaymentDetailsPage(
                                                          payment: {
                                                            'id': it.id,
                                                            'entity': it.entity,
                                                            'amount': it.amount,
                                                            'createdAt':
                                                                it.createdAt,
                                                            'endDate':
                                                                it.endDate,
                                                            'type': it.type,
                                                            'description':
                                                                it.description,
                                                          },
                                                          onEdit: (payment) async {
                                                            await _showEditDialog(p: payment);
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
                                                    color: Colors.red))),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.red, size: 32),
                                          onPressed: () =>
                                              _confirmDelete(it.id),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.black, size: 28),
                                          onPressed: () =>
                                              _showEditDialog(p: it),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.info_outline,
                                              color: Colors.blue, size: 28),
                                          tooltip: 'Detalles',
                                          onPressed: () async {
                                            await Navigator.of(context)
                                                .push(MaterialPageRoute(
                                                    builder: (_) =>
                                                        PaymentDetailsPage(
                                                            payment: {
                                                              'id': it.id,
                                                              'entity': it.entity,
                                                              'amount': it.amount,
                                                              'createdAt':
                                                                  it.createdAt,
                                                              'endDate':
                                                                  it.endDate,
                                                              'type': it.type,
                                                              'description':
                                                                  it.description,
                                                            },
                                                            onEdit: (payment) async {
                                                              await _showEditDialog(p: payment);
                                                            })));
                                          },
                                        ),
                                      ],
                                    ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            if (_loading) const CircularProgressIndicator(),
            const SizedBox(height: 12),
            _searchController.text.trim().isEmpty && _hasMoreItems && _items.length >= _pageSize
                ? ElevatedButton(
                    onPressed: _loading ? null : () => _fetch(next: true),
                    child: const Text('Ver Más'),
                  )
                : const SizedBox.shrink()
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

    // If there's a search query, perform server-side search so results show even if not paged locally
    if (q.isNotEmpty) {
      try {
        if (_userId == null) return;
        setState(() => _loading = true);
        final escaped = q.replaceAll('%', '\\%');
        // Búsqueda case-insensitive en nombre y descripción
        final res = await _supabase
            .from('payments')
            .select()
            .or("entity_name.ilike.%$escaped%,description.ilike.%$escaped%")
            .eq('user_id', _userId)
            .order('created_at', ascending: false);
        final List<Map<String, dynamic>> data = (res is List)
            ? List<Map<String, dynamic>>.from(res)
            : <Map<String, dynamic>>[];
        _filteredItems = data.map((e) => Payment.fromMap(e)).toList();
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
      // local filter
      _filteredItems = [..._items];
    }

    // Apply type filter
    if (_filterType != 'all') {
      _filteredItems =
          _filteredItems.where((p) => p.type == _filterType).toList();
    }

    // Recalculate totals
    _totalCobros = _filteredItems
        .where((p) => p.type == 'cobro')
        .fold(0.0, (s, p) => s + p.amount);
    _totalPagos = _filteredItems
        .where((p) => p.type == 'pago')
        .fold(0.0, (s, p) => s + p.amount);

    // count
    _totalCount = _filteredItems.length;

    if (mounted) setState(() {});
  }

  Widget _buildTopControls(bool wide, double maxWidth, InterfaceLabels labels) {
    if (wide) {
      return Row(
        children: [
          // Search bar (left)
          Expanded(
            flex: 4,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) {
                _applyFilter();
              },
            ),
          ),
          const SizedBox(width: 12),

          // Add button (center) - with transaction limit check
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _canAddTransactions ? () => _showEditDialog() : null,
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _canAddTransactions 
                        ? const LinearGradient(
                            colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                          )
                        : null,
                      color: _canAddTransactions ? null : Colors.grey,
                    ),
                    child: Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
              if (!_canAddTransactions && _maxTransactions != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Límite alcanzado\n($_currentTransactionCount/$_maxTransactions)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              if (_canAddTransactions && _maxTransactions != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '$_currentTransactionCount/$_maxTransactions',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),

          // Filter chips + Totals (right)
          const SizedBox(width: 12),
          // Filter chips (Todos / Cobros / Pagos)
          Wrap(
            spacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Todos'),
                selected: _filterType == 'all',
                onSelected: (_) {
                  setState(() => _filterType = 'all');
                  _applyFilter();
                },
              ),
              ChoiceChip(
                label: Text(labels.cobros),
                selected: _filterType == 'cobro',
                onSelected: (_) {
                  setState(() => _filterType = 'cobro');
                  _applyFilter();
                },
              ),
              ChoiceChip(
                label: Text(labels.pagos),
                selected: _filterType == 'pago',
                onSelected: (_) {
                  setState(() => _filterType = 'pago');
                  _applyFilter();
                },
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildTotalCard(labels.totalInvertidoLabel, _totalCobros),
                    const SizedBox(width: 8),
                    _buildTotalCard(labels.totalPagosLabel, _totalPagos),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Registros: $_totalCount',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      );
    }

    // Narrow layout: vertical stacking
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Buscar...',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onChanged: (v) => _applyFilter(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _canAddTransactions ? () => _showEditDialog() : null,
                borderRadius: BorderRadius.circular(26),
                child: Container(
                  width: 52,
                  height: 52,
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
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                      label: const Text('Todos'),
                      selected: _filterType == 'all',
                      onSelected: (_) {
                        setState(() => _filterType = 'all');
                        _applyFilter();
                      }),
                  ChoiceChip(
                      label: Text(labels.cobros),
                      selected: _filterType == 'cobro',
                      onSelected: (_) {
                        setState(() => _filterType = 'cobro');
                        _applyFilter();
                      }),
                  ChoiceChip(
                      label: Text(labels.pagos),
                      selected: _filterType == 'pago',
                      onSelected: (_) {
                        setState(() => _filterType = 'pago');
                        _applyFilter();
                      }),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildTotalCard(labels.totalInvertidoLabel, _totalCobros)),
            const SizedBox(width: 8),
            Expanded(child: _buildTotalCard(labels.totalPagosLabel, _totalPagos)),
          ],
        ),
        const SizedBox(height: 6),
        Text('Registros: $_totalCount',
            style: const TextStyle(color: Colors.black54)),
      ],
    );
  }

  Widget _buildTotalCard(String title, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text('\$${_formatAmount(value)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
