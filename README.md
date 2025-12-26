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
	user_id uuid references auth.users on delete cascade,
	client_name text not null,
	amount numeric not null,
	created_at timestamp with time zone default now()
);

---

Para restringir que cada usuario vea / modifique solo sus propios registros (Row Level Security):

1) Activar RLS en la tabla `payments` (SQL editor):

```sql
alter table public.payments enable row level security;
```

2) Crear políticas para que solo el owner (auth.uid()) pueda ver/insertar/editar/borrar sus filas:

```sql
-- Allow owners to SELECT their own rows
create policy "Allow select for owner" on public.payments
	for select using (auth.uid() = user_id);

-- Allow owners to INSERT only with their user_id
create policy "Allow insert for owner" on public.payments
	for insert with check (auth.uid() = user_id);

-- Allow owners to UPDATE only their rows
create policy "Allow update for owner" on public.payments
	for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Allow owners to DELETE only their rows
create policy "Allow delete for owner" on public.payments
	for delete using (auth.uid() = user_id);
```

3) Si aún no existe, habilita la extensión uuid_generate_v4:

```sql
create extension if not exists "uuid-ossp";
```

Nota: Después de esto, el backend rechazará operaciones que intenten manipular registros de otros usuarios; asegúrate de incluir `user_id` en las inserciones desde la app (como hace la pantalla de Pagos incluida).

Si ya tienes una tabla `payments` existente y quieres añadir `user_id`:

```sql
alter table public.payments add column if not exists user_id uuid references auth.users on delete cascade;
```

Recuerda poblar `user_id` para filas antiguas si corresponde y probar las políticas en el SQL editor.

---

Además, si quieres mantener datos de perfil (nombre, empresa, fecha de nacimiento), crea una tabla `profiles`:

```sql
create table public.profiles (
	id uuid references auth.users on delete cascade primary key,
	full_name text,
	company text,
	dob date,
	updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Profiles: select/update own" on public.profiles
	for select using (auth.uid() = id);

create policy "Profiles: update own" on public.profiles
	for update using (auth.uid() = id) with check (auth.uid() = id);

create policy "Profiles: insert own" on public.profiles
	for insert with check (auth.uid() = id);
```
```

La app incluye `lib/screens/payments_list.dart` con lista, añadir, editar y borrar. Usa el botón `Ver Más` para paginar (5 por página por defecto).

### Pruebas rápidas
- Regístrate con un email y confirma por correo si tu proyecto de Supabase requiere confirmación.
- Accede con tu email y contraseña.
- Ve a la pantalla "Lista de Pagos / Cobros" desde el icono en el AppBar para administrar pagos.
