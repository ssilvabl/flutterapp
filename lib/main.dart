import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'constants/supabase_config.dart';
import 'screens/landing.dart';
import 'screens/payments_list.dart';
import 'screens/splash_screen.dart';
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
        title: 'Flutter Demo',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const SplashScreen(child: AuthGate()),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        return const PaymentsListPage();
      }
      return const LandingPage();
  }
}
 
