import 'package:supabase_flutter/supabase_flutter.dart';

String friendlySupabaseMessage(
  Object e, {
  String fallback = 'Ocurrió un error. Inténtalo de nuevo.',
}) {
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login') ||
        msg.contains('invalid email or password') ||
        msg.contains('invalid password') ||
        msg.contains('invalid credentials') ||
        msg.contains('password is incorrect')) {
      return 'Contraseña incorrecta';
    }
    if (msg.contains('email not confirmed') ||
        msg.contains('email_not_confirmed') ||
        msg.contains('not allowed') ||
        msg.contains('email needs to be confirmed')) {
      return 'Debes confirmar tu correo';
    }
    if (msg.contains('user already registered')) {
      return 'Ya existe una cuenta con este email';
    }
    return e.message;
  }

  if (e is PostgrestException) {
    return 'No se pudo completar la operación';
  }

  return fallback;
}
