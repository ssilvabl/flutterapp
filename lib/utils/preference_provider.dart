import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'interface_labels.dart';

class PreferenceProvider extends ChangeNotifier {
  InterfacePreference _preference = InterfacePreference.prestamista;
  bool _isLoading = true;

  InterfacePreference get preference => _preference;
  InterfaceLabels get labels => InterfaceLabels(_preference);
  bool get isLoading => _isLoading;

  PreferenceProvider() {
    loadPreference();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.signedIn) {
        // Usuario inició sesión, recargar preferencias
        loadPreference();
      } else if (event == AuthChangeEvent.signedOut) {
        // Usuario cerró sesión, resetear a valores por defecto
        reset();
      }
    });
  }

  void reset() {
    _preference = InterfacePreference.prestamista;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadPreference() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final res = await Supabase.instance.client
          .from('profiles')
          .select('interface_preference')
          .eq('id', uid)
          .maybeSingle();

      if (res != null) {
        final prefStr = res['interface_preference'] as String?;
        _preference = InterfacePreferenceExtension.fromString(prefStr);
      }
    } catch (e) {
      debugPrint('Error loading preference: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePreference(InterfacePreference newPreference) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;

    try {
      await Supabase.instance.client.from('profiles').update({
        'interface_preference': newPreference.value,
      }).eq('id', uid);

      _preference = newPreference;
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating preference: $e');
      rethrow;
    }
  }
}

class PreferenceInheritedWidget extends InheritedNotifier<PreferenceProvider> {
  const PreferenceInheritedWidget({
    super.key,
    required PreferenceProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static PreferenceProvider? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<PreferenceInheritedWidget>()
        ?.notifier;
  }

  static PreferenceProvider watch(BuildContext context) {
    final provider = of(context);
    if (provider == null) {
      throw Exception('PreferenceProvider not found in widget tree');
    }
    return provider;
  }
}
