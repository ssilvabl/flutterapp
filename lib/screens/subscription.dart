import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/error_messages.dart';
import '../services/subscription_service.dart';
import '../services/mercadopago_service.dart';
import '../constants/mercadopago_config.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> with WidgetsBindingObserver {
  final _supabase = Supabase.instance.client;
  final _subscriptionService = SubscriptionService();
  final _mercadoPagoService = MercadoPagoService();
  final _appLinks = AppLinks();
  bool _loading = true;
  String _role = 'free';
  DateTime? _subscriptionStart;
  DateTime? _subscriptionEnd;
  bool _subscriptionCancelled = false; // Estado de renovación automática
  String? _lastProcessedLink; // Para evitar procesar el mismo link múltiples veces
  DateTime? _lastPaymentAttempt; // Para trackear cuando se inició un pago
  bool _checkingPayment = false; // Para evitar verificaciones múltiples

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Escuchar cambios de ciclo de vida
    _loadSubscriptionInfo();
    _initDeepLinks();
    // NO llamar _checkInitialLink() aquí para evitar procesar links antiguos
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      print('📱 App resumed - Verificando si hay pago pendiente...');
      _checkPendingPayment();
    }
  }

  Future<void> _checkPendingPayment() async {
    // Si hay un intento de pago reciente (últimos 5 minutos) y el rol es free
    if (_lastPaymentAttempt != null && 
        _role == 'free' && 
        !_checkingPayment &&
        DateTime.now().difference(_lastPaymentAttempt!) < const Duration(minutes: 5)) {
      
      setState(() => _checkingPayment = true);
      print('🔍 Verificando estado de pago automáticamente...');
      
      try {
        // Esperar un momento para que Mercado Pago procese
        await Future.delayed(const Duration(seconds: 2));
        
        // Verificar con Mercado Pago primero
        final userId = _supabase.auth.currentUser?.id;
        if (userId != null) {
          final paymentVerified = await _mercadoPagoService.verifyRecentPayment(userId);
          
          if (paymentVerified) {
            print('✅ Pago verificado automáticamente - Activando suscripción');
            await _subscriptionService.activateSubscription(userId);
            await _loadSubscriptionInfo();
            
            _lastPaymentAttempt = null; // Limpiar el intento
            
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Pago verificado! Suscripción activada exitosamente 🎉'),
                backgroundColor: Colors.green,
              ),
            );
            return; // Salir aquí si se verificó
          }
        }
        
        // Si no se verificó automáticamente, recargar info y preguntar
        await _loadSubscriptionInfo();
        
        // Si aún es free después de recargar, preguntar al usuario
        if (_role == 'free' && mounted) {
          print('⚠️ Pago no verificado automáticamente - Preguntando al usuario');
          _showPaymentConfirmationDialog();
        }
      } finally {
        if (mounted) {
          setState(() => _checkingPayment = false);
        }
      }
    }
  }

  void _showPaymentConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Verificar Pago'),
        content: const Text(
          '¿Completaste el pago exitosamente en Mercado Pago?',
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _lastPaymentAttempt = null; // Limpiar el intento
            },
            child: const Text('No / Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _manuallyActivateSubscription();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
            child: const Text('Sí, pagué'),
          ),
        ],
      ),
    );
  }

  Future<void> _manuallyActivateSubscription() async {
    // Mostrar loading mientras verifica
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Verificando pago con Mercado Pago...'),
          ],
        ),
      ),
    );
    
    try {
      print('🔐 Verificando pago con Mercado Pago...');
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Usuario no autenticado');
      }
      
      // Verificar con Mercado Pago si hay un pago aprobado reciente
      final paymentVerified = await _mercadoPagoService.verifyRecentPayment(userId);
      
      // Cerrar loading
      if (!mounted) return;
      Navigator.pop(context);
      
      if (paymentVerified) {
        print('✅ Pago verificado - Activando suscripción');
        await _subscriptionService.activateSubscription(userId);
        await _loadSubscriptionInfo();
        
        _lastPaymentAttempt = null; // Limpiar el intento
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Pago verificado! Suscripción activada exitosamente 🎉'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } else {
        print('❌ Pago no verificado');
        if (!mounted) return;
        
        // Mostrar diálogo explicando la situación
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Pago no encontrado'),
            content: const Text(
              'No pudimos verificar tu pago con Mercado Pago.\n\n'
              'Esto puede suceder si:\n'
              '• El pago aún está siendo procesado (intenta en unos minutos)\n'
              '• El pago fue rechazado\n'
              '• El pago no se completó\n\n'
              'Si completaste el pago, espera unos minutos y vuelve a intentar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _checkPendingPayment(); // Reintentar verificación
                },
                child: const Text('Verificar de nuevo'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Error al verificar/activar suscripción: $e');
      
      // Cerrar loading si está abierto
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al verificar pago: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  void _initDeepLinks() {
    // Escuchar deep links (móvil) cuando la app ya está abierta o se abre desde link
    _appLinks.uriLinkStream.listen((uri) {
      print('🔗 Deep link recibido en subscription: $uri');
      _processDeepLink(uri);
    }, onError: (err) {
      print('❌ Error en deep link listener: $err');
    });
  }

  void _processDeepLink(Uri uri) {
    final linkString = uri.toString();
    
    // Evitar procesar el mismo link múltiples veces
    if (_lastProcessedLink == linkString) {
      print('⚠️ Link ya procesado anteriormente, ignorando: $linkString');
      return;
    }
    
    print('🔍 Procesando deep link: $linkString');
    print('   Path: ${uri.path}');
    print('   Query params: ${uri.queryParameters}');
    
    // Marcar como procesado
    _lastProcessedLink = linkString;
    
    // Normalizar el path (puede venir como /success o /payment/success)
    final path = uri.path.toLowerCase();
    
    if (path.contains('success')) {
      print('✅ Pago exitoso detectado');
      _handlePaymentResponse(uri, success: true);
    } else if (path.contains('failure')) {
      print('❌ Pago fallido detectado');
      _handlePaymentResponse(uri, success: false);
    } else if (path.contains('pending')) {
      print('⏳ Pago pendiente detectado');
      _handlePaymentResponse(uri, pending: true);
    } else {
      print('⚠️ Path no reconocido: ${uri.path}');
    }
  }

  Future<void> _handlePaymentResponse(Uri uri, {bool success = false, bool pending = false}) async {
    final userId = _supabase.auth.currentUser?.id ?? '';
    
    print('🔔 _handlePaymentResponse llamado');
    print('   userId: $userId');
    print('   success: $success');
    print('   pending: $pending');

    if (!mounted) return;

    if (success) {
      // Pago aprobado - Activar suscripción
      try {
        print('🚀 Iniciando activación de suscripción...');
        await _subscriptionService.activateSubscription(userId);
        print('✅ Suscripción activada en base de datos');
        
        print('🔄 Recargando información de suscripción...');
        await _loadSubscriptionInfo();
        print('✅ Información recargada - Rol actual: $_role');
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Suscripción activada exitosamente! 🎉'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } catch (e) {
        print('❌ Error al activar suscripción: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al activar suscripción: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } else if (pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pago pendiente de confirmación. Te notificaremos cuando se complete.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El pago no fue completado'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    print('🔄 _loadSubscriptionInfo llamado');
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      print('   userId: $userId');
      if (userId == null) return;

      final response = await _supabase
          .from('profiles')
          .select('role, subscription_start, subscription_end, subscription_cancelled')
          .eq('id', userId)
          .single();
      
      print('📦 Respuesta de base de datos:');
      print('   role: ${response['role']}');
      print('   subscription_start: ${response['subscription_start']}');
      print('   subscription_end: ${response['subscription_end']}');
      print('   subscription_cancelled: ${response['subscription_cancelled']}');

      setState(() {
        _role = response['role'] as String? ?? 'free';
        _subscriptionCancelled = response['subscription_cancelled'] as bool? ?? false;
        final start = response['subscription_start'] as String?;
        final end = response['subscription_end'] as String?;
        
        if (start != null) {
          _subscriptionStart = DateTime.parse(start);
        }
        if (end != null) {
          _subscriptionEnd = DateTime.parse(end);
        }
      });
      
      print('✅ Estado actualizado - Rol: $_role, Cancelada: $_subscriptionCancelled');
    } catch (e) {
      print('❌ Error al cargar información: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar información: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPlanCard({
    required String title,
    required String price,
    required List<String> benefits,
    required Color color,
    required bool isCurrent,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent ? color : Colors.grey.shade300,
          width: isCurrent ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Actual',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              price,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            ...benefits.map((benefit) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      benefit,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubscribe() async {
    // MODO DEMO: Activar directamente sin pagar
    if (MercadoPagoConfig.demoMode) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('🎭 Modo Demo'),
          content: const Text(
            '⚠️ MODO DE PRUEBA ACTIVADO\n\n'
            'La suscripción se activará inmediatamente sin necesidad de pago.\n\n'
            'Este es solo para testing. En producción, configurar credenciales válidas de Mercado Pago.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Activar Demo'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      try {
        final userId = _supabase.auth.currentUser?.id;
        if (userId == null) throw Exception('Usuario no autenticado');

        // Activar suscripción directamente
        await _subscriptionService.activateSubscription(userId);
        await _loadSubscriptionInfo();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Suscripción activada en modo demo'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // MODO PRODUCCIÓN: Flujo normal con Mercado Pago
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suscripción Premium'),
        content: const Text(
          '¿Deseas suscribirte al plan Premium por \$25.000 COP/mes?\n\n'
          'Serás redirigido a Mercado Pago para completar el pago de forma segura.\n\n'
          'Una vez completado, regresa a la app y tu suscripción se activará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Pagar con Mercado Pago'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Mostrar loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final userId = _supabase.auth.currentUser?.id;
      final userEmail = _supabase.auth.currentUser?.email;
      
      if (userId == null || userEmail == null) {
        throw Exception('Usuario no autenticado');
      }

      // Obtener el nombre del usuario
      final profileResponse = await _supabase
          .from('profiles')
          .select('full_name, company')
          .eq('id', userId)
          .single();
      
      final userName = profileResponse['company'] ?? 
                      profileResponse['full_name'] ?? 
                      'Usuario';

      // Crear preferencia de pago en Mercado Pago
      final checkoutUrl = await _mercadoPagoService.createPaymentPreference(
        userId: userId,
        userEmail: userEmail,
        userName: userName,
      );

      // Cerrar loading
      if (!mounted) return;
      Navigator.of(context).pop();

      // Abrir en navegador externo
      final uri = Uri.parse(checkoutUrl);
      if (await canLaunchUrl(uri)) {
        // Marcar el momento del intento de pago
        setState(() {
          _lastPaymentAttempt = DateTime.now();
        });
        print('⏰ Marcando intento de pago: $_lastPaymentAttempt');
        
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Completa el pago en Mercado Pago. Al regresar, verificaremos automáticamente tu suscripción.'),
            duration: Duration(seconds: 5),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        throw Exception('No se pudo abrir Mercado Pago');
      }
    } catch (e) {
      // Cerrar loading si está abierto
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      
      if (!mounted) return;
      
      // Mostrar error detallado
      String errorMessage = 'Error al procesar el pago';
      if (e.toString().contains('Mercado Pago')) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      } else if (e.toString().contains('No se pudo abrir')) {
        errorMessage = 'No se pudo abrir el navegador para Mercado Pago';
      } else {
        errorMessage = 'Error: ${e.toString()}';
      }
      
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(errorMessage),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleToggleAutoRenewal(bool enable) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      if (enable) {
        // Reactivar renovación automática
        await _supabase.from('profiles').update({
          'subscription_cancelled': false,
        }).eq('id', userId);

        setState(() => _subscriptionCancelled = false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renovación automática reactivada'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Confirmar desactivación
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Desactivar renovación automática'),
            content: Text(
              'Tu suscripción Premium seguirá activa hasta el ${_subscriptionEnd != null ? DateFormat('dd/MM/yyyy').format(_subscriptionEnd!) : 'vencimiento'}.\n\n'
              'Después de esa fecha, volverás al plan Free.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Desactivar'),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        await _supabase.from('profiles').update({
          'subscription_cancelled': true,
        }).eq('id', userId);

        setState(() => _subscriptionCancelled = true);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Renovación automática desactivada'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleCancelSubscription() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Suscripción'),
        content: const Text(
          '¿Estás seguro de que deseas cancelar tu suscripción Premium?\n\n'
          'Tu plan seguirá activo hasta la fecha de vencimiento, pero no se renovará automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Confirmar cancelación'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      await _subscriptionService.cancelSubscription(userId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suscripción cancelada. Seguirá activa hasta la fecha de vencimiento.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e, fallback: 'Error al cancelar suscripción');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Suscripción'),
        backgroundColor: const Color(0xFF1F2323),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información actual
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1F2323), Color(0xFF2C3333)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Tu Plan Actual',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _role == 'premium' ? 'Premium' : 'Free',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_role == 'premium' && _subscriptionStart != null) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Inicio: ${DateFormat('dd/MM/yyyy').format(_subscriptionStart!)}',
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_subscriptionEnd != null)
                            Row(
                              children: [
                                const Icon(Icons.event, color: Colors.white70, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Vence: ${DateFormat('dd/MM/yyyy').format(_subscriptionEnd!)}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          const Divider(color: Colors.white24, height: 1),
                          const SizedBox(height: 16),
                          // Switch de renovación automática
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Renovación automática',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _subscriptionCancelled 
                                        ? 'Desactivada - Suscripción activa hasta el vencimiento'
                                        : 'Activa - Se renovará automáticamente',
                                      style: TextStyle(
                                        color: _subscriptionCancelled ? Colors.orange : Colors.green.shade300,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: !_subscriptionCancelled,
                                onChanged: (value) => _handleToggleAutoRenewal(value),
                                activeColor: Colors.green,
                                inactiveThumbColor: Colors.orange,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Planes Disponibles',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Plan Free
                  _buildPlanCard(
                    title: 'Free',
                    price: 'Gratuito',
                    benefits: [
                      'Hasta 15 registros',
                      '2 dispositivos en simultáneo',
                      'Funcionalidades básicas',
                    ],
                    color: Colors.grey,
                    isCurrent: _role == 'free',
                  ),
                  
                  // Plan Premium
                  _buildPlanCard(
                    title: 'Premium',
                    price: '\$25.000 COP / Mes',
                    benefits: [
                      'Hasta 3.000 registros',
                      '3 dispositivos en simultáneo',
                      'Todas las funcionalidades',
                      'Soporte prioritario',
                    ],
                    color: Colors.amber.shade700,
                    isCurrent: _role == 'premium',
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Botón de acción
                  if (_role == 'free')
                    // Usuario Free - Mostrar botón para suscribirse
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _handleSubscribe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Suscribirse a Premium - \$25.000 COP',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else if (_role == 'premium')
                    // Usuario Premium - Verificar si está expirado o próximo a expirar
                    Column(
                      children: [
                        if (_subscriptionEnd != null && _subscriptionEnd!.isBefore(DateTime.now()))
                          // Suscripción expirada - Mostrar botón para renovar
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _handleSubscribe,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Renovar Premium - \$25.000 COP',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else if (_subscriptionEnd != null && _subscriptionEnd!.difference(DateTime.now()).inDays <= 7)
                          // Próximo a expirar (7 días o menos) - Mostrar botón de renovación anticipada
                          Column(
                            children: [
                              if (!_subscriptionCancelled)
                                OutlinedButton(
                                  onPressed: _handleCancelSubscription,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red, width: 2),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancelar Suscripción',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _handleSubscribe,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text(
                                    'Renovar Ahora - \$25.000 COP',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else if (!_subscriptionCancelled)
                          // Suscripción activa - Solo mostrar cancelar
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton(
                              onPressed: _handleCancelSubscription,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red, width: 2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Cancelar Suscripción',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }
}
