import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/web_file_picker.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/vaca_oferta.dart';
import '../utils/image_utils.dart';
import '../utils/price_input_formatter.dart';

double _uploadProgress = 0.0;
final ImagePicker _picker = ImagePicker();
final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
final TextEditingController _cantidadController = TextEditingController();
final TextEditingController _pesoMedioController = TextEditingController();
final TextEditingController _razaController = TextEditingController();
final TextEditingController _edadController = TextEditingController();
final TextEditingController _codigoPostalController = TextEditingController();
List<XFile> _fotos = [];
final Map<String, Uint8List> _fotoBytesCache = <String, Uint8List>{};
XFile? _video;
Uint8List? _videoBytesCache;
DateTime? _fechaSalida;
String? _diferenciaRespuesta; // 'si' o 'no'
final TextEditingController _diferenciaController = TextEditingController();

String _fotoCacheKey(XFile file) => '${file.path}|${file.name}';

class VenderVacasScreen extends StatefulWidget {
  const VenderVacasScreen({super.key});

  @override
  State<VenderVacasScreen> createState() => _VenderVacasScreenState();
}

class _VenderVacasScreenState extends State<VenderVacasScreen> {
  // Panel de errores para desarrollo
  final List<String> _devErrors = [];
  OverlayEntry? _errorOverlay;
  // Removed unused _devUserEmail field

  @override
  void initState() {
    super.initState();
    _setupAutologin();
    _setupErrorPanel();
  }

  // Autologin solo en modo desarrollo
  Future<void> _setupAutologin() async {
    if (kDebugMode) {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('dev_user_email');
      if (email != null && email.isNotEmpty) {
        // (Dev) Previously stored dev email available: $email
        // Field _devUserEmail removed; keep hook for potential future auto-login.
        // AquÃ­ podrÃ­as llamar a tu mÃ©todo de login automÃ¡tico
        // await AuthService.loginWithEmail(email);
      }
    }
  }

  // Panel de errores solo en modo desarrollo
  void _setupErrorPanel() {
    if (kDebugMode) {
      FlutterError.onError = (FlutterErrorDetails details) {
        setState(() {
          _devErrors.add(details.exceptionAsString());
        });
        if (_errorOverlay == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showErrorOverlay();
          });
        }
      };
    }
  }

  void _showErrorOverlay() {
    if (_errorOverlay != null) return;
    _errorOverlay = OverlayEntry(
      builder: (context) => Positioned(
        right: 16,
        top: 80,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[900]?.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Errores tÃ©cnicos',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._devErrors.reversed
                    .take(5)
                    .map((e) => Text(e, style: const TextStyle(color: Colors.white, fontSize: 12))),
                if (_devErrors.length > 5)
                  Text('... (${_devErrors.length - 5} mÃ¡s)',
                      style: const TextStyle(color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _devErrors.clear();
                      });
                      _errorOverlay?.remove();
                      _errorOverlay = null;
                    },
                    child: const Text('Cerrar', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_errorOverlay!);
  }

  String? _formaPagoSeleccionada;
  bool _isSavingDeclaracion = false;
  bool _isSavingDeclaracionSinDefecto = false;
  bool _isSavingOferta = false;
  bool _declaracionGuardada = false;

  Widget _campoFormaPago() {
    return SizedBox(
      width: 640,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Forma de pago',
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0288D1)),
          ),
        ),
        items: const [
          DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
          DropdownMenuItem(value: 'transferencia', child: Text('Transferencia')),
          DropdownMenuItem(value: '15dias', child: Text('15 dÃ­as')),
          DropdownMenuItem(value: '30dias', child: Text('30 dÃ­as')),
          DropdownMenuItem(value: '60dias', child: Text('60 dÃ­as')),
          DropdownMenuItem(value: '90dias', child: Text('90 dÃ­as')),
        ],
        value: _formaPagoSeleccionada,
        onChanged: (value) {
          setState(() {
            _formaPagoSeleccionada = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoTexto(String label, TextInputType tipo,
      {String? unidad,
      int? maxLength,
      String? Function(String?)? validator,
      TextEditingController? controller}) {
    return SizedBox(
      width: 640,
      child: TextFormField(
        decoration: InputDecoration(
          labelText: unidad != null ? '$label ($unidad)' : label,
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0288D1)),
          ),
          counterText: '', // Oculta el contador de caracteres
        ),
        keyboardType: tipo,
        style: const TextStyle(fontSize: 14, height: 1.5),
        minLines: 1,
        maxLength: maxLength,
        validator: validator,
        controller: controller,
        inputFormatters: [
          if (label == 'Edad (meses)') FilteringTextInputFormatter.allow(RegExp(r'^[0-9]{0,2}')),
        ],
      ),
    );
  }

  String? _tipoPrecioSeleccionado;
  final TextEditingController _precioController = TextEditingController();

  Widget _campoDropdown() {
    return SizedBox(
      width: 640,
      child: DropdownButtonFormField<String>(
        decoration: InputDecoration(
          labelText: 'Tipo de precio',
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0288D1)),
          ),
        ),
        items: const [
          DropdownMenuItem(value: 'eur_kg', child: Text('â‚¬/kg')),
          DropdownMenuItem(value: 'eur_unidad', child: Text('â‚¬/unidad')),
          DropdownMenuItem(value: 'eur_libra', child: Text('â‚¬/libra')),
          DropdownMenuItem(value: 'eur_arroba', child: Text('â‚¬/@')),
        ],
        value: _tipoPrecioSeleccionado,
        onChanged: (value) {
          setState(() {
            _tipoPrecioSeleccionado = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoPrecio() {
    TextInputType tipoTeclado = TextInputType.number;
    String? Function(String?)? validador;
    int maxLength = 4;
    final TextEditingController controller = _precioController;
    List<TextInputFormatter>? inputFormatters;
    if (_tipoPrecioSeleccionado == 'eur_unidad') {
      // 4 cifras, sin decimales
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,4}$');
        if (!exp.hasMatch(value)) return context.tr('errorPriceMax4NoDecimals');
        return null;
      };
      tipoTeclado = TextInputType.number;
      maxLength = 4;
      inputFormatters = [FilteringTextInputFormatter.digitsOnly];
    } else if (_tipoPrecioSeleccionado == 'eur_kg' ||
        _tipoPrecioSeleccionado == 'eur_libra' ||
        _tipoPrecioSeleccionado == 'eur_arroba') {
      // dos cifras y un decimal, formateo automÃ¡tico
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,2}([\.,][0-9])?$');
        if (!exp.hasMatch(value)) return context.tr('errorPriceMax2OneDecimal');
        return null;
      };
      tipoTeclado = const TextInputType.numberWithOptions(decimal: true);
      maxLength = 5; // visual only; enforced by formatter ignoring separator
      inputFormatters = [
        PriceInputFormatter(maxIntegerDigits: 2, maxDecimalDigits: 1),
      ];
      // No reasignar el controller, siempre usar _precioController
    }
    return SizedBox(
      width: 640,
      child: TextFormField(
        controller: controller,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: 'Precio',
          filled: true,
          fillColor: const Color(0xFFE3F2FD),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0288D1)),
          ),
        ),
        keyboardType: tipoTeclado,
        style: const TextStyle(fontSize: 14, height: 1.5),
        minLines: 1,
        enabled: _tipoPrecioSeleccionado != null,
        validator: validador,
        maxLength: maxLength,
      ),
    );
  }

  Widget _campoFotos() {
    return SizedBox(
      width: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              List<XFile> pickedFiles = <XFile>[];
              try {
                if (kIsWeb) {
                  final picked = await pickImagesWeb();
                  for (final p in picked) {
                    final name = p.name.isEmpty
                        ? 'foto_${DateTime.now().millisecondsSinceEpoch}.jpg'
                        : p.name;
                    final xf = XFile.fromData(p.bytes, name: name);
                    _fotoBytesCache[_fotoCacheKey(xf)] = p.bytes;
                    pickedFiles.add(xf);
                  }
                } else {
                  pickedFiles = await _picker.pickMultiImage();
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al abrir selector de fotos: $e')),
                );
                return;
              }
              if (!mounted) return;
              if (pickedFiles.isEmpty) return;
              const int max = 10;
              final int remaining = max - _fotos.length;
              if (remaining <= 0) {
                final loc = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('errorMax10Photos'))),
                );
                return;
              }
              // Evitar duplicados por path o nombre
              final List<XFile> newUnique = pickedFiles
                  .where((x) => !_fotos.any((e) => e.path == x.path || e.name == x.name))
                  .toList();
              final List<XFile> toAdd = newUnique.take(remaining).toList();
              final List<XFile> cacheable = <XFile>[];
              for (final file in toAdd) {
                try {
                  final key = _fotoCacheKey(file);
                  _fotoBytesCache[key] = _fotoBytesCache[key] ?? await file.readAsBytes();
                  cacheable.add(file);
                } catch (_) {
                  // Best effort: if caching fails, upload will try reading again.
                }
              }
              setState(() {
                _fotos.addAll(cacheable);
              });
              final int skippedForLimit = (newUnique.length - toAdd.length).clamp(0, 1000);
              final loc = AppLocalizations.of(context);
              if (skippedForLimit > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(loc.tf('photosAddedCountWithMax', {
                    'count': cacheable.length.toString(),
                    'max': max.toString(),
                  }))),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(loc.tf('photosAddedCount', {
                    'count': cacheable.length.toString(),
                  }))),
                );
              }
            },
            icon: const Icon(Icons.add_a_photo, color: Color(0xFF0288D1)),
            label: const Text('Seleccionar fotos',
                style: TextStyle(color: Color(0xFF0288D1), fontSize: 14)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFB3E5FC)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              XFile? picked;
              Uint8List? cachedBytes;
              try {
                if (kIsWeb) {
                  final p = await pickVideoWeb();
                  if (p != null) {
                    final name = p.name.isEmpty
                        ? 'video_${DateTime.now().millisecondsSinceEpoch}.mp4'
                        : p.name;
                    cachedBytes = p.bytes;
                    picked = XFile.fromData(p.bytes, name: name);
                  }
                } else {
                  picked = await _picker.pickVideo(
                    source: ImageSource.gallery,
                    maxDuration: const Duration(seconds: 10),
                  );
                }
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al abrir selector de video: $e')),
                );
                return;
              }
              if (!mounted) return;
              if (picked != null) {
                if (cachedBytes == null) {
                  try {
                    cachedBytes = await picked.readAsBytes();
                  } catch (_) {
                    // Best effort: if caching fails, upload will try reading again.
                  }
                }
                setState(() {
                  _video = picked;
                  _videoBytesCache = cachedBytes;
                });
                final loc = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('videoSelectedOk'))),
                );
              }
            },
            icon: const Icon(Icons.videocam, color: Color(0xFF0288D1)),
            label: const Text('Seleccionar video (<= 10s)',
                style: TextStyle(color: Color(0xFF0288D1), fontSize: 14)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFB3E5FC)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB3E5FC)),
            ),
            child: Text(
              'Diagnostico archivos\n'
              'Fotos listas: ${_fotoBytesCache.length}/${_fotos.length}\n'
              'Video listo: ${_video == null ? 'no seleccionado' : (_videoBytesCache != null ? 'si' : 'no')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF004d26)),
            ),
          ),
          const SizedBox(height: 8),
          if (_fotos.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fotos.asMap().entries.map((entry) {
                final int index = entry.key;
                final file = entry.value;
                final cachedBytes = _fotoBytesCache[_fotoCacheKey(file)];
                final Widget img = cachedBytes != null
                    ? Image.memory(cachedBytes, width: 80, height: 80, fit: BoxFit.cover)
                    : const SizedBox(
                        width: 80,
                        height: 80,
                        child: ColoredBox(
                          color: Color(0xFFE3F2FD),
                          child: Icon(Icons.broken_image, color: Colors.redAccent),
                        ),
                      );
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: img),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () {
                            setState(() {
                              final removed = _fotos.removeAt(index);
                              _fotoBytesCache.remove(_fotoCacheKey(removed));
                            });
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close, size: 16, color: Colors.redAccent),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          if (_video != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.videocam, size: 20, color: Color(0xFF0288D1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _video!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar video',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _video = null;
                      _videoBytesCache = null;
                    });
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF004d26),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
        actions: const [],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: Image.asset(
                'assets/images/logobysapp.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    const Text('Vender vacas',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        // color: Color(0xFFE3F2FD), // azul muy suave
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            _campoDropdown(),
                            const SizedBox(height: 4),
                            _campoPrecio(),
                            const SizedBox(height: 4),
                            _campoTexto(
                              'Cantidad',
                              TextInputType.number,
                              maxLength: 3,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[0-9]{1,3}$');
                                if (!exp.hasMatch(value)) return context.tr('errorMax3Digits');
                                return null;
                              },
                              controller: _cantidadController,
                            ),
                            const SizedBox(height: 4),
                            _campoTexto(
                              'Peso medio (por animal)',
                              TextInputType.number,
                              unidad: _tipoPrecioSeleccionado == 'eur_libra'
                                  ? 'libras'
                                  : _tipoPrecioSeleccionado == 'eur_arroba'
                                      ? '@'
                                      : 'kg',
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[0-9]{1,4}$');
                                if (!exp.hasMatch(value)) return context.tr('errorMax4Digits');
                                return null;
                              },
                              controller: _pesoMedioController,
                            ),
                            const SizedBox(height: 4),
                            _campoTexto(
                              'Raza',
                              TextInputType.text,
                              maxLength: 10,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘]{1,10}$');
                                if (!exp.hasMatch(value)) {
                                  return context.tr('errorLettersOnlyMax10');
                                }
                                return null;
                              },
                              controller: _razaController,
                            ),
                            const SizedBox(height: 4),
                            _campoTexto(
                              'Edad (meses)',
                              TextInputType.number,
                              maxLength: 2,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La edad es obligatoria.';
                                }
                                final exp = RegExp(r'^[0-9]{1,2}$');
                                if (!exp.hasMatch(value)) return context.tr('errorMax2Digits');
                                return null;
                              },
                              controller: _edadController,
                            ),
                            const SizedBox(height: 4),
                            _campoFormaPago(),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 640,
                              child: GestureDetector(
                                onTap: () async {
                                  final DateTime? picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _fechaSalida = picked;
                                    });
                                  }
                                },
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: 'Fecha estimada de salida',
                                      filled: true,
                                      fillColor: const Color(0xFFE3F2FD),
                                      contentPadding:
                                          const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                                      isDense: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: Color(0xFF0288D1)),
                                      ),
                                    ),
                                    controller: TextEditingController(
                                        text: _fechaSalida == null
                                            ? ''
                                            : '${_fechaSalida!.day.toString().padLeft(2, '0')}/${_fechaSalida!.month.toString().padLeft(2, '0')}/${_fechaSalida!.year}'),
                                    readOnly: true,
                                    style: const TextStyle(fontSize: 14, height: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _campoTexto(
                              'CÃ³digo Postal',
                              TextInputType.number,
                              maxLength: 5,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[0-9]{1,5}$');
                                if (!exp.hasMatch(value)) return context.tr('errorMax5Digits');
                                return null;
                              },
                              controller: _codigoPostalController,
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 640,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                      'Â¿Existe algÃºn animal con algÃºn defecto o diferencia con el resto del grupo?',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _diferenciaRespuesta == 'si'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuesta == 'si'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuesta = 'si';
                                            _declaracionGuardada = false;
                                          });
                                        },
                                        child: const Text('SÃ­'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _diferenciaRespuesta == 'no'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuesta == 'no'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuesta = 'no';
                                            _diferenciaController.clear();
                                            _declaracionGuardada = false;
                                          });
                                        },
                                        child: const Text('No'),
                                      ),
                                    ],
                                  ),
                                  if (_diferenciaRespuesta == 'si') ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _diferenciaController,
                                      decoration: InputDecoration(
                                        labelText: 'Describa la diferencia o defecto',
                                        filled: true,
                                        fillColor: const Color(0xFFE3F2FD),
                                        contentPadding: const EdgeInsets.symmetric(
                                            vertical: 10, horizontal: 16),
                                        isDense: true,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFFB3E5FC)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Color(0xFF0288D1)),
                                        ),
                                      ),
                                      keyboardType: TextInputType.text,
                                      style: const TextStyle(fontSize: 14, height: 1.5),
                                      minLines: 1,
                                      maxLength: 40,
                                      onChanged: (_) {
                                        if (_declaracionGuardada) {
                                          setState(() {
                                            _declaracionGuardada = false;
                                          });
                                        }
                                      },
                                      inputFormatters: [
                                        FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                                        LengthLimitingTextInputFormatter(40),
                                      ],
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return context.tr('errorDefectDescriptionRequired');
                                        }
                                        final exp = RegExp(
                                            r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘ ]{1,40}$');
                                        if (!exp.hasMatch(value)) {
                                          return context.tr('errorLettersOnlyNoNumbersMax30');
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingDeclaracion ||
                                              _declaracionGuardada ||
                                              _diferenciaController.text.trim().isEmpty
                                          ? null
                                          : () async {
                                              final descripcion = _diferenciaController.text.trim();
                                              final exp = RegExp(
                                                  r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘ ]{1,40}$');
                                              if (!exp.hasMatch(descripcion)) {
                                                final loc = AppLocalizations.of(context);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        loc.t('errorLettersOnlyNoNumbersMax30')),
                                                  ),
                                                );
                                                return;
                                              }
                                              setState(() {
                                                _isSavingDeclaracion = true;
                                              });
                                              await Future<void>.delayed(
                                                  const Duration(seconds: 2));
                                              setState(() {
                                                _isSavingDeclaracion = false;
                                                _declaracionGuardada = true;
                                              });
                                              final loc = AppLocalizations.of(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                    content: Text(loc.t('declarationSavedOk'))),
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracion
                                            ? Colors.grey
                                            : _declaracionGuardada
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracion
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardada
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.check, color: Colors.white),
                                                    const SizedBox(width: 8),
                                                    Text(AppLocalizations.of(context)
                                                        .t('declarationSaved')),
                                                  ],
                                                )
                                              : Text(AppLocalizations.of(context).t('accept')),
                                    ),
                                  ],
                                  if (_diferenciaRespuesta == 'no') ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Declaro bajo mi responsabilidad que no se conoce defecto o diferencia en ningÃºn animal del grupo.',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed:
                                          _isSavingDeclaracionSinDefecto || _declaracionGuardada
                                              ? null
                                              : () async {
                                                  setState(() {
                                                    _isSavingDeclaracionSinDefecto = true;
                                                  });
                                                  // Simula guardar declaraciÃ³n en Firebase si lo necesitas
                                                  await Future<void>.delayed(
                                                      const Duration(seconds: 2));
                                                  setState(() {
                                                    _isSavingDeclaracionSinDefecto = false;
                                                    _declaracionGuardada = true;
                                                  });
                                                  final loc = AppLocalizations.of(context);
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                        content: Text(loc.t('declarationSavedOk'))),
                                                  );
                                                },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracionSinDefecto
                                            ? Colors.grey
                                            : _declaracionGuardada
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracionSinDefecto
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardada
                                              ? Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.check, color: Colors.white),
                                                    const SizedBox(width: 8),
                                                    Text(AppLocalizations.of(context)
                                                        .t('declarationSaved')),
                                                  ],
                                                )
                                              : Text(AppLocalizations.of(context).t('accept')),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            _campoFotos(),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _isSavingOferta
                                  ? null
                                  : () async {
                                      // ValidaciÃ³n de campos obligatorios
                                      final loc = AppLocalizations.of(context);
                                      final bilingual = context.isBi;
                                      String add(String key) =>
                                          bilingual ? AppLocalizations.bilingual(key) : loc.t(key);
                                      String errorMsg = '';
                                      if (_tipoPrecioSeleccionado == null ||
                                          _tipoPrecioSeleccionado!.isEmpty) {
                                        errorMsg += '${add('errorPriceTypeRequired')}\n';
                                      }
                                      if (_precioController.text.isEmpty) {
                                        errorMsg += '${add('errorPriceRequired')}\n';
                                      }
                                      if (_cantidadController.text.isEmpty) {
                                        errorMsg += '${add('errorQuantityRequired')}\n';
                                      }
                                      if (_pesoMedioController.text.isEmpty) {
                                        errorMsg += '${add('errorAvgWeightRequired')}\n';
                                      }
                                      if (_razaController.text.isEmpty) {
                                        errorMsg += '${add('errorBreedRequired')}\n';
                                      }
                                      if (_edadController.text.isEmpty) {
                                        errorMsg += '${add('errorAgeRequired')}\n';
                                      }
                                      if (_formaPagoSeleccionada == null ||
                                          _formaPagoSeleccionada!.isEmpty) {
                                        errorMsg += '${add('errorPaymentFormRequired')}\n';
                                      }
                                      if (_fechaSalida == null) {
                                        errorMsg += '${add('errorExitDateRequired')}\n';
                                      }
                                      if (_codigoPostalController.text.isEmpty) {
                                        errorMsg += '${add('errorPostalCodeRequired')}\n';
                                      }
                                      if (_diferenciaRespuesta == null ||
                                          _diferenciaRespuesta!.isEmpty) {
                                        errorMsg += '${add('errorDefectChoiceRequired')}\n';
                                      }
                                      if (_diferenciaRespuesta == 'si' &&
                                          _diferenciaController.text.isEmpty) {
                                        errorMsg += '${add('errorDefectDescriptionRequired')}\n';
                                      }
                                      if (_fotos.length < 2) {
                                        errorMsg += '${add('errorAtLeast2Photos')}\n';
                                      }
                                      if (_fotos.length > 10) {
                                        errorMsg += '${add('errorMax10Photos')}\n';
                                      }
                                      if (!_declaracionGuardada) {
                                        errorMsg +=
                                            '${add('errorDeclarationAcceptanceRequired')}\n';
                                      }
                                      if (errorMsg.isNotEmpty ||
                                          !(_formKey.currentState?.validate() ?? false)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(content: Text(errorMsg.trim())));
                                        return;
                                      }
                                      setState(() {
                                        _isSavingOferta = true;
                                        _uploadProgress = 0.0;
                                      });
                                      final List<String> uploadedUrls = [];
                                      try {
                                        final user = FirebaseAuth.instance.currentUser;
                                        if (user == null) throw 'Usuario no autenticado';
                                        final docRef = FirebaseFirestore.instance
                                            .collection('vacas_ofertas')
                                            .doc();
                                        final offerId = docRef.id;
                                        // Subida concurrente en lotes para acelerar
                                        const int concurrency = 6;
                                        int completed = 0;
                                        for (int start = 0;
                                            start < _fotos.length;
                                            start += concurrency) {
                                          final int end = (start + concurrency) > _fotos.length
                                              ? _fotos.length
                                              : (start + concurrency);
                                          final futures = <Future<void>>[];
                                          for (int i = start; i < end; i++) {
                                            futures.add(() async {
                                              final file = _fotos[i];
                                              final ref = FirebaseStorage.instance.ref().child(
                                                  'users/${user.uid}/offers/vacas/$offerId/photos/$i.jpg');
                                              try {
                                                final raw = _fotoBytesCache[_fotoCacheKey(file)];
                                                if (raw == null) {
                                                  throw Exception(
                                                      'No se pudo leer la imagen ${file.name}');
                                                }
                                                final prepared = await prepareImageForUpload(raw);
                                                final uploadTask = ref.putData(
                                                  prepared,
                                                  SettableMetadata(contentType: 'image/jpeg'),
                                                );
                                                await uploadTask;
                                                final url = await ref.getDownloadURL();
                                                uploadedUrls.add(url);
                                                setState(() {
                                                  completed++;
                                                  _uploadProgress = completed / _fotos.length;
                                                });
                                              } catch (imgErr) {
                                                print(
                                                    'Error al subir la imagen ${file.name}: $imgErr');
                                                if (kDebugMode) {
                                                  setState(() {
                                                    _devErrors.add(
                                                        'Error al subir la imagen ${file.name}: $imgErr');
                                                  });
                                                }
                                                rethrow;
                                              }
                                            }());
                                          }
                                          try {
                                            await Future.wait(futures);
                                          } catch (e) {
                                            setState(() {
                                              _isSavingOferta = false;
                                              _uploadProgress = 0.0;
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                content: Text(loc.tf('errorUploadingImage', {
                                              'file': '',
                                              'error': e.toString(),
                                            }))));
                                            return;
                                          }
                                        }
                                        String? uploadedVideoUrl;
                                        if (_video != null) {
                                          try {
                                            final refVideo = FirebaseStorage.instance.ref().child(
                                                'users/${user.uid}/offers/vacas/$offerId/video.mp4');
                                            final vbytes =
                                                _videoBytesCache ?? await _video!.readAsBytes();
                                            final vtask = refVideo.putData(
                                              vbytes,
                                              SettableMetadata(contentType: 'video/mp4'),
                                            );
                                            await vtask;
                                            uploadedVideoUrl = await refVideo.getDownloadURL();
                                          } catch (vErr) {
                                            print('Error al subir el video: $vErr');
                                            if (kDebugMode) {
                                              setState(() {
                                                _devErrors.add('Error al subir el video: $vErr');
                                              });
                                            }
                                            // No abortar por fallo de video; continuar sin video
                                          }
                                        }
                                        final oferta = VacaOferta(
                                          tipoPrecio: _tipoPrecioSeleccionado ?? '',
                                          precio: _precioController.text.replaceAll(',', '.'),
                                          cantidad: _cantidadController.text,
                                          pesoMedio: _pesoMedioController.text,
                                          raza: _razaController.text,
                                          edadMeses: _edadController.text,
                                          formaPago: _formaPagoSeleccionada ?? '',
                                          fechaSalida: _fechaSalida == null
                                              ? ''
                                              : '${_fechaSalida!.year}-${_fechaSalida!.month.toString().padLeft(2, '0')}-${_fechaSalida!.day.toString().padLeft(2, '0')}',
                                          codigoPostal: _codigoPostalController.text,
                                          diferenciaRespuesta: _diferenciaRespuesta ?? '',
                                          diferenciaDescripcion: _diferenciaRespuesta == 'si'
                                              ? _diferenciaController.text
                                              : '',
                                          fotos: uploadedUrls,
                                          videoUrl: uploadedVideoUrl,
                                        );
                                        final ofertaMap = oferta.toMap();
                                        ofertaMap['vendedor'] = user.uid;
                                        ofertaMap['uid'] = user.uid;
                                        ofertaMap['aceptadoComprador'] = false;
                                        ofertaMap['comprador'] = null;
                                        await docRef.set(ofertaMap);
                                        print('[DEBUG] Oferta subida con ID: ${docRef.id}');
                                        setState(() {
                                          _isSavingOferta = false;
                                          _uploadProgress = 0.0;
                                        });
                                        if (mounted) {
                                          Navigator.of(context).pushNamedAndRemoveUntil(
                                            '/home',
                                            (route) => false,
                                            arguments: {'toastKey': 'offerPublishedSuccessSimple'},
                                          );
                                        }
                                      } catch (e) {
                                        print('Error al subir la oferta: $e');
                                        if (kDebugMode) {
                                          setState(() {
                                            _devErrors.add('Error al subir la oferta: $e');
                                          });
                                        }
                                        setState(() {
                                          _isSavingOferta = false;
                                          _uploadProgress = 0.0;
                                        });
                                        final loc = AppLocalizations.of(context);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                              content: Text(loc.tf('errorUploadingOffer', {
                                            'error': e.toString(),
                                          }))),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isSavingOferta ? Colors.grey : const Color(0xFF004d26),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 40),
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: _isSavingOferta
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                                value:
                                                    _uploadProgress > 0 ? _uploadProgress : null)),
                                        if (_uploadProgress > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                                'Subiendo fotos: ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                                                style: const TextStyle(
                                                    color: Colors.white, fontSize: 12)),
                                          ),
                                      ],
                                    )
                                  : const Text('Publicar oferta'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
