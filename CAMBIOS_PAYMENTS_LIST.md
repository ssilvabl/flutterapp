# Cambios Implementados en payments_list.dart

## ✅ Cambios YA Implementados:

1. ✅ **Conteo total de registros** - Variable `_totalCountDB` muestra el conteo real
2. ✅ **Scroll infinito** - ScrollController con listener `_onScroll`
3. ✅ **Tiempo real** - M\u00e9todos `_setupRealtime()` con suscripciones
4. ✅ **Montos actuales** - M\u00e9todo `_calculateCurrentAmounts()` calcula desde movimientos
5. ✅ **Preferencias de ordenamiento** - M\u00e9todos `_loadSortPreference()` y `_saveSortPreference()`

## 📝 Cambios que Debes Aplicar Manualmente:

### 1. Actualizar `_applyFilter()` para incluir ordenamiento

Busca el m\u00e9todo `_applyFilter()` (aprox l\u00ednea 1050) y reemplaza con:

```dart
Future<void> _applyFilter() async {
  final q = _searchController.text.trim();

  // If there's a search query, perform server-side search
  if (q.isNotEmpty) {
    try {
      if (_userId == null) return;
      setState(() => _loading = true);
      final escaped = q.replaceAll('%', '\\\\%');
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
      await _calculateCurrentAmounts(_filteredItems);
    } catch (e) {
      if (!mounted) return;
      final msg = friendlySupabaseMessage(e, fallback: 'Error al buscar');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  } else {
    _filteredItems = [..._items];
  }

  // Apply type filter
  if (_filterType != 'all') {
    _filteredItems = _filteredItems.where((p) => p.type == _filterType).toList();
  }

  // Apply sort order
  switch (_sortOrder) {
    case 'date_desc':
      _filteredItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      break;
    case 'date_asc':
      _filteredItems.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      break;
    case 'alpha':
      _filteredItems.sort((a, b) => a.entity.toLowerCase().compareTo(b.entity.toLowerCase()));
      break;
    case 'amount_desc':
      _filteredItems.sort((a, b) => b.currentAmount.compareTo(a.currentAmount));
      break;
    case 'amount_asc':
      _filteredItems.sort((a, b) => a.currentAmount.compareTo(b.currentAmount));
      break;
  }

  // Recalculate totals usando currentAmount
  _totalCobros = _filteredItems
      .where((p) => p.type == 'cobro')
      .fold(0.0, (s, p) => s + p.currentAmount);
  _totalPagos = _filteredItems
      .where((p) => p.type == 'pago')
      .fold(0.0, (s, p) => s + p.currentAmount);

  _totalCount = _filteredItems.length;

  if (mounted) setState(() {});
}
```

### 2. Agregar bot\u00f3n de filtro en `_buildTopControls()`

En el m\u00e9todo `_buildTopControls()`, despu\u00e9s del bot\u00f3n de agregar (+), agrega:

```dart
const SizedBox(width: 12),
// Bot\u00f3n de filtro/ordenamiento
IconButton(
  icon: const Icon(Icons.sort),
  tooltip: 'Ordenar',
  onPressed: () async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ordenar por'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Fecha (M\u00e1s reciente)'),
              leading: Radio<String>(
                value: 'date_desc',
                groupValue: _sortOrder,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ),
            ListTile(
              title: const Text('Fecha (M\u00e1s antiguo)'),
              leading: Radio<String>(
                value: 'date_asc',
                groupValue: _sortOrder,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ),
            ListTile(
              title: const Text('Alfab\u00e9tico (A-Z)'),
              leading: Radio<String>(
                value: 'alpha',
                groupValue: _sortOrder,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ),
            ListTile(
              title: const Text('Monto (Mayor)'),
              leading: Radio<String>(
                value: 'amount_desc',
                groupValue: _sortOrder,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ),
            ListTile(
              title: const Text('Monto (Menor)'),
              leading: Radio<String>(
                value: 'amount_asc',
                groupValue: _sortOrder,
                onChanged: (v) => Navigator.pop(ctx, v),
              ),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await _saveSortPreference(result);
    }
  },
),
```

### 3. Actualizar contador de registros para mostrar total

Busca `Text('Registros: $_totalCount'` y reemplaza con:

```dart
Text('Registros: $_totalCount${_totalCountDB > 0 ? ' de $_totalCountDB' : ''}',
    style: const TextStyle(color: Colors.black54)),
```

### 4. Hacer toda la tarjeta cliqueable

Busca el `itemBuilder` en el ListView (aprox l\u00ednea 840) y envuelve el Container completo con GestureDetector:

```dart
itemBuilder: (context, index) {
  final it = _filteredItems[index];
  final screenWidth = MediaQuery.of(context).size.width;
  final showPopupActions = screenWidth < 600;
  
  return GestureDetector(
    onTap: () async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PaymentDetailsPage(
            payment: {
              'id': it.id,
              'entity': it.entity,
              'amount': it.currentAmount, // Usar currentAmount
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
        Expanded(
          child: Container(
            // ... resto del c\u00f3digo del container
          ),
        ),
        // ... resto de acciones
      ],
    ),
  );
},
```

### 5. Actualizar el Text que muestra el monto para usar currentAmount

Busca todas las ocurrencias de `it.amount` dentro del ListView y reemplaza con `it.currentAmount`:

```dart
Text(
  '\$${_formatAmount(it.currentAmount)}', // Cambiar it.amount por it.currentAmount
  style: const TextStyle(color: Colors.white),
  textAlign: TextAlign.right
)
```

### 6. Eliminar el bot\u00f3n "Ver M\u00e1s" (ya no es necesario con scroll infinito)

Busca y ELIMINA este bloque (aprox l\u00ednea 1118):

```dart
_searchController.text.trim().isEmpty && _hasMoreItems && _items.length >= _pageSize
    ? ElevatedButton(
        onPressed: _loading ? null : () => _fetch(next: true),
        child: const Text('Ver M\u00e1s'),
      )
    : const SizedBox.shrink()
```

### 7. Actualizar el ListView para usar ScrollController

Busca el `ListView.separated` y aseg\u00farate de que tenga el controller:

```dart
ListView.separated(
  controller: _scrollController, // AGREGAR ESTA L\u00cdNEA
  physics: const AlwaysScrollableScrollPhysics(),
  itemCount: _filteredItems.length + (_loadingMore ? 1 : 0), // Agregar indicador de carga
  // ... resto del c\u00f3digo
)
```

### 8. Agregar indicador de carga al final de la lista

Modifica el `itemBuilder` para mostrar loading cuando se carga m\u00e1s:

```dart
itemBuilder: (context, index) {
  // Mostrar indicador de carga al final
  if (index == _filteredItems.length) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(),
      ),
    );
  }
  
  final it = _filteredItems[index];
  // ... resto del c\u00f3digo
},
```

## \ud83d\udd27 C\u00f3mo Aplicar:

1. Abre `payments_list.dart`
2. Busca cada secci\u00f3n mencionada arriba
3. Aplica los cambios uno por uno
4. Guarda el archivo
5. Ejecuta `flutter pub get` si es necesario
6. Prueba la app

## \u2705 Resultado Final:

- \u2705 Contador muestra total de registros desde el inicio
- \u2705 Bot\u00f3n de filtro con 5 opciones de ordenamiento
- \u2705 Preferencia de ordenamiento guardada
- \u2705 Toda la tarjeta es cliqueable
- \u2705 Scroll infinito funcionando
- \u2705 Valores actuales (no iniciales) mostrados
- \u2705 Actualizaci\u00f3n en tiempo real activada
- \u2705 Funciona en iOS y Android
