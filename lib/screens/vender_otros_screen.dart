import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../models/otro_oferta.dart';
import '../utils/image_utils.dart';
import '../utils/price_input_formatter.dart';
import '../utils/web_file_picker.dart';

// Copia exacta de la pantalla de vender vacas, pero para otros.
double _uploadProgressOtros = 0.0;
final ImagePicker _pickerOtros = ImagePicker();
final GlobalKey<FormState> _formKeyOtros = GlobalKey<FormState>();
final TextEditingController _cantidadControllerOtros = TextEditingController();
final TextEditingController _pesoMedioControllerOtros = TextEditingController();
final TextEditingController _razaControllerOtros = TextEditingController();
final TextEditingController _edadControllerOtros = TextEditingController();
final TextEditingController _codigoPostalControllerOtros = TextEditingController();
List<XFile> _fotosOtros = [];
final Map<String, Uint8List> _fotoBytesCacheOtros = <String, Uint8List>{};
XFile? _videoOtros;
Uint8List? _videoBytesCacheOtros;
DateTime? _fechaSalidaOtros;
String? _diferenciaRespuestaOtros; // 'si' o 'no'
final TextEditingController _diferenciaControllerOtros = TextEditingController();

String _fotoCacheKeyOtros(XFile file) => '${file.path}|${file.name}';

class VenderOtrosScreen extends StatefulWidget {
  const VenderOtrosScreen({super.key});

  @override
  State<VenderOtrosScreen> createState() => _VenderOtrosScreenState();
}

class _VenderOtrosScreenState extends State<VenderOtrosScreen> {
  final List<String> _devErrors = [];
  OverlayEntry? _errorOverlay;
  // Removed unused _devUserEmail field (was causing lint warning)

  @override
  void initState() {
    super.initState();
    _setupAutologin();
    _setupErrorPanel();
  }

  Future<void> _setupAutologin() async {
    if (kDebugMode) {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('dev_user_email');
      if (email != null && email.isNotEmpty) {
        setState(() {
          // was: _devUserEmail = email; (removed unused variable)
        });
      }
    }
  }

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
                const Text('Errores técnicos',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._devErrors.reversed
                    .take(5)
                    .map((e) => Text(e, style: const TextStyle(color: Colors.white, fontSize: 12))),
                if (_devErrors.length > 5)
                  Text('... ([${_devErrors.length - 5} más)',
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

  String? _formaPagoSeleccionadaOtros;
  bool _isSavingDeclaracionOtros = false;
  bool _isSavingDeclaracionSinDefectoOtros = false;
  bool _isSavingOfertaOtros = false;
  bool _declaracionGuardadaOtros = false;

  Widget _campoFormaPagoOtros() {
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
          DropdownMenuItem(value: '15dias', child: Text('15 días')),
          DropdownMenuItem(value: '30dias', child: Text('30 días')),
          DropdownMenuItem(value: '60dias', child: Text('60 días')),
          DropdownMenuItem(value: '90dias', child: Text('90 días')),
        ],
        value: _formaPagoSeleccionadaOtros,
        onChanged: (value) {
          setState(() {
            _formaPagoSeleccionadaOtros = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoTextoOtros(String label, TextInputType tipo,
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
          counterText: '',
        ),
        keyboardType: tipo,
        style: const TextStyle(fontSize: 14, height: 1.5),
        minLines: 1,
        maxLength: maxLength,
        validator: validator,
        controller: controller,
        inputFormatters: [
          if (label == 'Cantidad' ||
              label == 'Peso medio (por animal)' ||
              label == 'Edad (meses)' ||
              label == 'Código Postal')
            FilteringTextInputFormatter.digitsOnly,
          if (label == 'Raza') FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ]')),
        ],
      ),
    );
  }

  String? _tipoPrecioSeleccionadoOtros;
  final TextEditingController _precioControllerOtros = TextEditingController();

  Widget _campoDropdownOtros() {
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
          DropdownMenuItem(value: 'eur_kg', child: Text('€/kg')),
          DropdownMenuItem(value: 'eur_unidad', child: Text('€/unidad')),
          DropdownMenuItem(value: 'eur_libra', child: Text('€/libra')),
          DropdownMenuItem(value: 'eur_arroba', child: Text('€/@')),
        ],
        value: _tipoPrecioSeleccionadoOtros,
        onChanged: (value) {
          setState(() {
            _tipoPrecioSeleccionadoOtros = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoPrecioOtros() {
    TextInputType tipoTeclado = TextInputType.number;
    String? Function(String?)? validador;
    int maxLength = 4;
    final TextEditingController controller = _precioControllerOtros;
    List<TextInputFormatter>? inputFormatters;
    if (_tipoPrecioSeleccionadoOtros == 'eur_unidad') {
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,4}$');
        if (!exp.hasMatch(value)) return 'Máximo 4 cifras, sin decimales';
        return null;
      };
      tipoTeclado = TextInputType.number;
      maxLength = 4;
      inputFormatters = [FilteringTextInputFormatter.digitsOnly];
    } else if (_tipoPrecioSeleccionadoOtros == 'eur_kg' ||
        _tipoPrecioSeleccionadoOtros == 'eur_libra' ||
        _tipoPrecioSeleccionadoOtros == 'eur_arroba') {
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,2}([\.,][0-9])?$');
        if (!exp.hasMatch(value)) return 'Máximo 2 cifras y 1 decimal';
        return null;
      };
      tipoTeclado = const TextInputType.numberWithOptions(decimal: true);
      maxLength = 5;
      inputFormatters = [
        PriceInputFormatter(maxIntegerDigits: 2, maxDecimalDigits: 1),
      ];
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
        enabled: _tipoPrecioSeleccionadoOtros != null,
        validator: validador,
        maxLength: maxLength,
      ),
    );
  }

  Widget _campoFotosOtros() {
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
                    _fotoBytesCacheOtros[_fotoCacheKeyOtros(xf)] = p.bytes;
                    pickedFiles.add(xf);
                  }
                } else {
                  pickedFiles = await _pickerOtros.pickMultiImage();
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
              final int remaining = max - _fotosOtros.length;
              if (remaining <= 0) {
                final loc = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('errorMax10Photos'))),
                );
                return;
              }
              final List<XFile> newUnique = pickedFiles
                  .where((x) => !_fotosOtros.any((e) => e.path == x.path || e.name == x.name))
                  .toList();
              final List<XFile> toAdd = newUnique.take(remaining).toList();
              final List<XFile> cacheable = <XFile>[];
              for (final file in toAdd) {
                try {
                  final key = _fotoCacheKeyOtros(file);
                  _fotoBytesCacheOtros[key] = _fotoBytesCacheOtros[key] ?? await file.readAsBytes();
                  cacheable.add(file);
                } catch (_) {
                  // Best effort: if caching fails, upload will try reading again.
                }
              }
              setState(() {
                _fotosOtros.addAll(cacheable);
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
                  picked = await _pickerOtros.pickVideo(
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
                  _videoOtros = picked;
                  _videoBytesCacheOtros = cachedBytes;
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
              'Fotos listas: ${_fotoBytesCacheOtros.length}/${_fotosOtros.length}\n'
              'Video listo: ${_videoOtros == null ? 'no seleccionado' : (_videoBytesCacheOtros != null ? 'si' : 'no')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF004d26)),
            ),
          ),
          const SizedBox(height: 8),
          if (_fotosOtros.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fotosOtros.asMap().entries.map((entry) {
                final int index = entry.key;
                final file = entry.value;
                final cachedBytes = _fotoBytesCacheOtros[_fotoCacheKeyOtros(file)];
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
                              final removed = _fotosOtros.removeAt(index);
                              _fotoBytesCacheOtros.remove(_fotoCacheKeyOtros(removed));
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
          if (_videoOtros != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.videocam, size: 20, color: Color(0xFF0288D1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _videoOtros!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar video',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _videoOtros = null;
                      _videoBytesCacheOtros = null;
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
                    const Text('Vender otros',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Form(
                        key: _formKeyOtros,
                        child: Column(
                          children: [
                            _campoDropdownOtros(),
                            const SizedBox(height: 4),
                            _campoPrecioOtros(),
                            const SizedBox(height: 4),
                            _campoTextoOtros(
                              'Cantidad',
                              TextInputType.number,
                              maxLength: 3,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La cantidad es obligatoria.';
                                }
                                final exp = RegExp(r'^[0-9]{1,3}$');
                                if (!exp.hasMatch(value)) return 'Máximo 3 cifras';
                                return null;
                              },
                              controller: _cantidadControllerOtros,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOtros(
                              'Peso medio (por animal)',
                              TextInputType.number,
                              unidad: _tipoPrecioSeleccionadoOtros == 'eur_libra'
                                  ? 'libras'
                                  : _tipoPrecioSeleccionadoOtros == 'eur_arroba'
                                      ? '@'
                                      : 'kg',
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'El peso medio es obligatorio.';
                                }
                                final exp = RegExp(r'^[0-9]{1,4}$');
                                if (!exp.hasMatch(value)) return 'Máximo 4 cifras';
                                return null;
                              },
                              controller: _pesoMedioControllerOtros,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOtros(
                              'Raza',
                              TextInputType.text,
                              maxLength: 10,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La raza es obligatoria.';
                                }
                                final exp = RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ]{1,10}$');
                                if (!exp.hasMatch(value)) return 'Solo letras, máximo 10';
                                return null;
                              },
                              controller: _razaControllerOtros,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOtros(
                              'Edad (meses)',
                              TextInputType.number,
                              maxLength: 2,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La edad es obligatoria.';
                                }
                                final exp = RegExp(r'^[0-9]{1,2}$');
                                if (!exp.hasMatch(value)) return 'Máximo 2 cifras';
                                return null;
                              },
                              controller: _edadControllerOtros,
                            ),
                            const SizedBox(height: 4),
                            _campoFormaPagoOtros(),
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
                                      _fechaSalidaOtros = picked;
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
                                        text: _fechaSalidaOtros == null
                                            ? ''
                                            : '${_fechaSalidaOtros!.day.toString().padLeft(2, '0')}/${_fechaSalidaOtros!.month.toString().padLeft(2, '0')}/${_fechaSalidaOtros!.year}'),
                                    readOnly: true,
                                    style: const TextStyle(fontSize: 14, height: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOtros(
                              'Código Postal',
                              TextInputType.number,
                              maxLength: 5,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[0-9]{1,5}$');
                                if (!exp.hasMatch(value)) return 'Máximo 5 cifras';
                                return null;
                              },
                              controller: _codigoPostalControllerOtros,
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: 640,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                      '¿Existe algún animal con algún defecto o diferencia con el resto del grupo?',
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _diferenciaRespuestaOtros == 'si'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuestaOtros == 'si'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuestaOtros = 'si';
                                            _declaracionGuardadaOtros = false;
                                          });
                                        },
                                        child: const Text('Sí'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _diferenciaRespuestaOtros == 'no'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuestaOtros == 'no'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuestaOtros = 'no';
                                            _diferenciaControllerOtros.clear();
                                            _declaracionGuardadaOtros = false;
                                          });
                                        },
                                        child: const Text('No'),
                                      ),
                                    ],
                                  ),
                                  if (_diferenciaRespuestaOtros == 'si') ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _diferenciaControllerOtros,
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
                                        if (_declaracionGuardadaOtros) {
                                          setState(() {
                                            _declaracionGuardadaOtros = false;
                                          });
                                        }
                                      },
                                      inputFormatters: [
                                        // Bloquea cualquier dígito (0-9) incluso si se pega desde el portapapeles
                                        FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                                        // Refuerza el límite de longitud en tiempo real
                                        LengthLimitingTextInputFormatter(40),
                                      ],
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Debes describir la diferencia o defecto (solo letras)';
                                        }
                                        final exp = RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ ]{1,40}$');
                                        if (!exp.hasMatch(value)) {
                                          return 'Solo letras, sin números, máximo 40';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingDeclaracionOtros ||
                                              _declaracionGuardadaOtros ||
                                              _diferenciaControllerOtros.text.trim().isEmpty
                                          ? null
                                          : () async {
                                              final descripcion =
                                                  _diferenciaControllerOtros.text.trim();
                                              final exp =
                                                  RegExp(r'^[a-zA-ZáéíóúÁÉÍÓÚüÜñÑ ]{1,40}$');
                                              if (!exp.hasMatch(descripcion)) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content:
                                                        Text('Solo letras, sin números, máximo 40'),
                                                  ),
                                                );
                                                return;
                                              }
                                              setState(() {
                                                _isSavingDeclaracionOtros = true;
                                              });
                                              await Future<void>.delayed(
                                                  const Duration(seconds: 2));
                                              setState(() {
                                                _isSavingDeclaracionOtros = false;
                                                _declaracionGuardadaOtros = true;
                                              });
                                              final loc = AppLocalizations.of(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                    content: Text(loc.t('declarationSavedOk'))),
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracionOtros
                                            ? Colors.grey
                                            : _declaracionGuardadaOtros
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracionOtros
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardadaOtros
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
                                  if (_diferenciaRespuestaOtros == 'no') ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Declaro bajo mi responsabilidad que no se conoce defecto o diferencia en ningún animal del grupo.',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingDeclaracionSinDefectoOtros ||
                                              _declaracionGuardadaOtros
                                          ? null
                                          : () async {
                                              setState(() {
                                                _isSavingDeclaracionSinDefectoOtros = true;
                                              });
                                              await Future<void>.delayed(
                                                  const Duration(seconds: 2));
                                              setState(() {
                                                _isSavingDeclaracionSinDefectoOtros = false;
                                                _declaracionGuardadaOtros = true;
                                              });
                                              final loc = AppLocalizations.of(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                    content: Text(loc.t('declarationSavedOk'))),
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracionSinDefectoOtros
                                            ? Colors.grey
                                            : _declaracionGuardadaOtros
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracionSinDefectoOtros
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardadaOtros
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
                            _campoFotosOtros(),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _isSavingOfertaOtros
                                  ? null
                                  : () async {
                                      final loc = AppLocalizations.of(context);
                                      final bilingual = context.isBi;
                                      String add(String key) =>
                                          bilingual ? AppLocalizations.bilingual(key) : loc.t(key);
                                      String errorMsg = '';
                                      if (_tipoPrecioSeleccionadoOtros == null ||
                                          _tipoPrecioSeleccionadoOtros!.isEmpty) {
                                        errorMsg += '${add('errorPriceTypeRequired')}\n';
                                      }
                                      if (_precioControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorPriceRequired')}\n';
                                      }
                                      if (_cantidadControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorQuantityRequired')}\n';
                                      }
                                      if (_pesoMedioControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorAvgWeightRequired')}\n';
                                      }
                                      if (_razaControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorBreedRequired')}\n';
                                      }
                                      if (_edadControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorAgeRequired')}\n';
                                      }
                                      if (_formaPagoSeleccionadaOtros == null ||
                                          _formaPagoSeleccionadaOtros!.isEmpty) {
                                        errorMsg += '${add('errorPaymentFormRequired')}\n';
                                      }
                                      if (_fechaSalidaOtros == null) {
                                        errorMsg += '${add('errorExitDateRequired')}\n';
                                      }
                                      if (_codigoPostalControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorPostalCodeRequired')}\n';
                                      }
                                      if (_diferenciaRespuestaOtros == null ||
                                          _diferenciaRespuestaOtros!.isEmpty) {
                                        errorMsg += '${add('errorDefectChoiceRequired')}\n';
                                      }
                                      if (_diferenciaRespuestaOtros == 'si' &&
                                          _diferenciaControllerOtros.text.isEmpty) {
                                        errorMsg += '${add('errorDefectDescriptionRequired')}\n';
                                      }
                                      if (_fotosOtros.length < 2) {
                                        errorMsg += '${add('errorAtLeast2Photos')}\n';
                                      }
                                      if (_fotosOtros.length > 10) {
                                        errorMsg += '${add('errorMax10Photos')}\n';
                                      }
                                      if (errorMsg.isNotEmpty ||
                                          !(_formKeyOtros.currentState?.validate() ?? false)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(content: Text(errorMsg.trim())));
                                        return;
                                      }
                                      setState(() {
                                        _isSavingOfertaOtros = true;
                                        _uploadProgressOtros = 0.0;
                                      });
                                      final List<String> uploadedUrls = [];
                                      try {
                                        final user = FirebaseAuth.instance.currentUser;
                                        if (user == null) throw 'Usuario no autenticado';
                                        final docRef = FirebaseFirestore.instance
                                            .collection('otros_ofertas')
                                            .doc();
                                        final offerId = docRef.id;
                                        for (int i = 0; i < _fotosOtros.length; i++) {
                                          final file = _fotosOtros[i];
                                          final ref = FirebaseStorage.instance.ref().child(
                                              'users/${user.uid}/offers/otros/$offerId/photos/$i.jpg');
                                          try {
                                            final raw =
                                                _fotoBytesCacheOtros[_fotoCacheKeyOtros(file)];
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
                                              _uploadProgressOtros = (i + 1) / _fotosOtros.length;
                                            });
                                          } catch (imgErr) {
                                            print('Error al subir la imagen ${file.name}: $imgErr');
                                            if (kDebugMode) {
                                              setState(() {
                                                _devErrors.add(
                                                    'Error al subir la imagen ${file.name}: $imgErr');
                                              });
                                            }
                                            setState(() {
                                              _isSavingOfertaOtros = false;
                                              _uploadProgressOtros = 0.0;
                                            });
                                            final loc = AppLocalizations.of(context);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                  content: Text(loc.tf('errorUploadingImage', {
                                                'file': file.name,
                                                'error': imgErr.toString(),
                                              }))),
                                            );
                                            return;
                                          }
                                        }
                                        String? uploadedVideoUrl;
                                        if (_videoOtros != null) {
                                          try {
                                            final refVideo = FirebaseStorage.instance.ref().child(
                                                'users/${user.uid}/offers/otros/$offerId/video.mp4');
                                            final vbytes = _videoBytesCacheOtros ??
                                                await _videoOtros!.readAsBytes();
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
                                          }
                                        }
                                        final oferta = OtroOferta(
                                          tipoPrecio: _tipoPrecioSeleccionadoOtros ?? '',
                                          precio: _precioControllerOtros.text.replaceAll(',', '.'),
                                          cantidad: _cantidadControllerOtros.text,
                                          pesoMedio: _pesoMedioControllerOtros.text,
                                          raza: _razaControllerOtros.text,
                                          edadMeses: _edadControllerOtros.text,
                                          formaPago: _formaPagoSeleccionadaOtros ?? '',
                                          fechaSalida: _fechaSalidaOtros == null
                                              ? ''
                                              : '${_fechaSalidaOtros!.year}-${_fechaSalidaOtros!.month.toString().padLeft(2, '0')}-${_fechaSalidaOtros!.day.toString().padLeft(2, '0')}',
                                          codigoPostal: _codigoPostalControllerOtros.text,
                                          diferenciaRespuesta: _diferenciaRespuestaOtros ?? '',
                                          diferenciaDescripcion: _diferenciaRespuestaOtros == 'si'
                                              ? _diferenciaControllerOtros.text
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
                                          _isSavingOfertaOtros = false;
                                          _uploadProgressOtros = 0.0;
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
                                          _isSavingOfertaOtros = false;
                                          _uploadProgressOtros = 0.0;
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
                                    _isSavingOfertaOtros ? Colors.grey : const Color(0xFF004d26),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 40),
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: _isSavingOfertaOtros
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                                value: _uploadProgressOtros > 0
                                                    ? _uploadProgressOtros
                                                    : null)),
                                        if (_uploadProgressOtros > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                                AppLocalizations.of(context)
                                                    .tf('uploadingPhotosProgress', {
                                                  'percent': (_uploadProgressOtros * 100)
                                                      .toStringAsFixed(0),
                                                }),
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
