enum InterfacePreference {
  prestamista,  // Cobros y Pagos (default)
  personal,     // Ingresos y Gastos
  inversionista, // Activos y Pasivos
}

extension InterfacePreferenceExtension on InterfacePreference {
  String get value {
    switch (this) {
      case InterfacePreference.prestamista:
        return 'prestamista';
      case InterfacePreference.personal:
        return 'personal';
      case InterfacePreference.inversionista:
        return 'inversionista';
    }
  }

  String get displayName {
    switch (this) {
      case InterfacePreference.prestamista:
        return 'Prestamista';
      case InterfacePreference.personal:
        return 'Personal';
      case InterfacePreference.inversionista:
        return 'Inversionista';
    }
  }

  static InterfacePreference fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'personal':
        return InterfacePreference.personal;
      case 'inversionista':
        return InterfacePreference.inversionista;
      case 'prestamista':
      default:
        return InterfacePreference.prestamista;
    }
  }
}

class InterfaceLabels {
  final InterfacePreference preference;

  InterfaceLabels(this.preference);

  // Labels para "cobro" según la preferencia
  String get cobro {
    switch (preference) {
      case InterfacePreference.prestamista:
        return 'Cobro';
      case InterfacePreference.personal:
        return 'Ingreso';
      case InterfacePreference.inversionista:
        return 'Activo';
    }
  }

  String get cobros {
    switch (preference) {
      case InterfacePreference.prestamista:
        return 'Cobros';
      case InterfacePreference.personal:
        return 'Ingresos';
      case InterfacePreference.inversionista:
        return 'Activos';
    }
  }

  // Labels para "pago" según la preferencia
  String get pago {
    switch (preference) {
      case InterfacePreference.prestamista:
        return 'Pago';
      case InterfacePreference.personal:
        return 'Gasto';
      case InterfacePreference.inversionista:
        return 'Pasivo';
    }
  }

  String get pagos {
    switch (preference) {
      case InterfacePreference.prestamista:
        return 'Pagos';
      case InterfacePreference.personal:
        return 'Gastos';
      case InterfacePreference.inversionista:
        return 'Pasivos';
    }
  }

  // Métodos helper para obtener el label correcto basado en el tipo
  String getLabel(String type, {bool plural = false}) {
    if (type == 'cobro') {
      return plural ? cobros : cobro;
    } else {
      return plural ? pagos : pago;
    }
  }

  // Labels para usar en placeholders y títulos
  String get agregarCobro => 'Agregar $cobro';
  String get agregarPago => 'Agregar $pago';
  String get listaCobros => 'Lista de $cobros';
  String get listaPagos => 'Lista de $pagos';
  String get totalCobros => 'Total $cobros';
  String get totalPagos => 'Total $pagos';
  String get nuevoCobro => 'Nuevo $cobro';
  String get nuevoPago => 'Nuevo $pago';
  String get editarCobro => 'Editar $cobro';
  String get editarPago => 'Editar $pago';
  String get detallesCobro => 'Detalles del $cobro';
  String get detallesPago => 'Detalles del $pago';
}
