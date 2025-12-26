# Cómo cambiar el ícono de la app

## Pasos para actualizar el ícono:

1. **Guardar la imagen del ícono:**
   - Guarda la imagen del ícono (el archivo PNG adjunto con el símbolo de dólar y engranaje) en la carpeta: `assets/icons/app_icon.png`
   - La imagen debe ser cuadrada, preferiblemente de 1024x1024 píxeles o más grande

2. **Instalar dependencias:**
   ```bash
   flutter pub get
   ```

3. **Generar los íconos:**
   ```bash
   flutter pub run flutter_launcher_icons
   ```

4. **Limpiar y reconstruir la app:**
   ```bash
   flutter clean
   flutter build apk  # Para Android
   # o
   flutter build ios  # Para iOS
   ```

## Notas:
- El paquete `flutter_launcher_icons` está configurado en el archivo `pubspec.yaml`
- Se generarán automáticamente íconos para todas las resoluciones necesarias
- Para Android se crearán íconos adaptativos con fondo blanco
- El ícono se aplicará tanto a Android como a iOS

## Ubicación de los íconos generados:
- **Android:** `android/app/src/main/res/mipmap-*/`
- **iOS:** `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
