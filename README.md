# sepagos

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Configurar Supabase (Auth)

1. Crea un proyecto en https://app.supabase.com/ y copia la `URL` y la `anon key`.
2. Rellena `lib/constants/supabase_config.dart` con `supabaseUrl` y `supabaseAnonKey`.
3. Ejecuta `flutter pub get` y lanza la app.

Nota: Este proyecto incluye pantallas básicas de `login` y `registro` en `lib/screens`.

## CRUD de Pagos

Para usar la pantalla de pagos crea una tabla en Supabase llamada `payments` con la siguiente SQL (SQL Editor → Run):

```sql
create table public.payments (
	id uuid default uuid_generate_v4() primary key,
	client_name text not null,
	amount numeric not null,
	created_at timestamp with time zone default now()
);
```

La app incluye `lib/screens/payments_list.dart` con lista, añadir, editar y borrar. Usa el botón `Ver Más` para paginar (5 por página por defecto).

### Pruebas rápidas
- Regístrate con un email y confirma por correo si tu proyecto de Supabase requiere confirmación.
- Accede con tu email y contraseña.
- Ve a la pantalla "Lista de Pagos / Cobros" desde el icono en el AppBar para administrar pagos.
