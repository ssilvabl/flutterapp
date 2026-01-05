import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'constants/supabase_config.dart';
import 'screens/landing.dart';
import 'screens/payments_list.dart';
import 'screens/splash_screen.dart';
import 'screens/subscription.dart';
import 'services/subscription_service.dart';
import 'utils/preference_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  runApp(const MyApp());
} 

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final PreferenceProvider _preferenceProvider = PreferenceProvider();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final _appLinks = AppLinks();
  final _subscriptionService = SubscriptionService();

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    print('🔧 Inicializando listener de deep links global...');
    
    // Verificar si la app se abrió desde un deep link (cuando estaba cerrada)
    _appLinks.getInitialAppLink().then((uri) {
      if (uri != null) {
        print('🌍 Deep link inicial detectado: $uri');
        print('   Scheme: ${uri.scheme}');
        print('   Host: ${uri.host}');
        print('   Path: ${uri.path}');
        _handleDeepLink(uri);
      } else {
        print('ℹ️ No hay deep link inicial');
      }
    }).catchError((err) {
      print('❌ Error al obtener deep link inicial: $err');
    });
    
    // Escuchar deep links cuando la app ya está abierta
    _appLinks.uriLinkStream.listen((uri) {
      print('🌍 Deep link recibido globalmente (stream): $uri');
      print('   Scheme: ${uri.scheme}');
      print('   Host: ${uri.host}');
      print('   Path: ${uri.path}');
      _handleDeepLink(uri);
    }, onError: (err) {
      print('❌ Error en deep link global: $err');
    });
    
    print('✅ Listener de deep links configurado');
  }

  Future<void> _handleDeepLink(Uri uri) async {
    final path = uri.path.toLowerCase();
    print('🔍 Procesando deep link global: $path');
    
    if (path.contains('payment')) {
      if (path.contains('success')) {
        print('✅ Pago exitoso - Activando suscripción...');
        await _activateSubscriptionFromDeepLink();
      } else if (path.contains('failure')) {
        print('❌ Pago fallido');
        _showMessage('El pago no fue completado', isError: true);
      } else if (path.contains('pending')) {
        print('⏳ Pago pendiente');
        _showMessage('Pago pendiente de confirmación', isError: false);
      }
    }
  }

  Future<void> _activateSubscriptionFromDeepLink() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        print('⚠️ No hay usuario autenticado');
        return;
      }
      
      print('🚀 Activando suscripción para usuario: $userId');
      await _subscriptionService.activateSubscription(userId);
      print('✅ Suscripción activada exitosamente');
      
      _showMessage('¡Suscripción activada exitosamente! 🎉', isError: false);
      
      // Navegar a la pantalla de suscripción para que vea los cambios
      _navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (context) => const SubscriptionPage()),
      );
    } catch (e) {
      print('❌ Error al activar suscripción: $e');
      _showMessage('Error al activar suscripción: $e', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    final context = _navigatorKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _preferenceProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PreferenceInheritedWidget(
      provider: _preferenceProvider,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'Sepagos',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('es', 'ES'),
        ],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const SplashScreen(child: AuthGate()),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    // Escuchar cambios de autenticación para reconstruir
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return const PaymentsListPage();
    }
    return const LandingPage();
  }
}
 
