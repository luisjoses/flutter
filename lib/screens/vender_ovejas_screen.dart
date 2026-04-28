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
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/oveja_oferta.dart';
import '../utils/image_utils.dart';
import '../utils/price_input_formatter.dart';

// Copia exacta de la pantalla de vender vacas, pero para ovejas.
double _uploadProgressOvejas = 0.0;
final ImagePicker _pickerOvejas = ImagePicker();
final GlobalKey<FormState> _formKeyOvejas = GlobalKey<FormState>();
final TextEditingController _cantidadControllerOvejas = TextEditingController();
final TextEditingController _pesoMedioControllerOvejas = TextEditingController();
final TextEditingController _razaControllerOvejas = TextEditingController();
final TextEditingController _edadControllerOvejas = TextEditingController();
final TextEditingController _codigoPostalControllerOvejas = TextEditingController();
List<XFile> _fotosOvejas = [];
final Map<String, Uint8List> _fotoBytesCacheOvejas = <String, Uint8List>{};
XFile? _videoOvejas;
Uint8List? _videoBytesCacheOvejas;
DateTime? _fechaSalidaOvejas;
String? _diferenciaRespuestaOvejas; // 'si' o 'no'
final TextEditingController _diferenciaControllerOvejas = TextEditingController();

String _fotoCacheKeyOvejas(XFile file) => '${file.path}|${file.name}';

class VenderOvejasScreen extends StatefulWidget {
  const VenderOvejasScreen({super.key});

  @override
  State<VenderOvejasScreen> createState() => _VenderOvejasScreenState();
}

class _VenderOvejasScreenState extends State<VenderOvejasScreen> {
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
                const Text('Errores tÃ©cnicos',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._devErrors.reversed
                    .take(5)
                    .map((e) => Text(e, style: const TextStyle(color: Colors.white, fontSize: 12))),
                if (_devErrors.length > 5)
                  Text('... ([${_devErrors.length - 5} mÃ¡s)',
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

  String? _formaPagoSeleccionadaOvejas;
  bool _isSavingDeclaracionOvejas = false;
  bool _isSavingDeclaracionSinDefectoOvejas = false;
  bool _isSavingOfertaOvejas = false;
  bool _declaracionGuardadaOvejas = false;

  Widget _campoFormaPagoOvejas() {
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
        value: _formaPagoSeleccionadaOvejas,
        onChanged: (value) {
          setState(() {
            _formaPagoSeleccionadaOvejas = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoTextoOvejas(String label, TextInputType tipo,
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
              label == 'CÃ³digo Postal')
            FilteringTextInputFormatter.digitsOnly,
          if (label == 'Raza')
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘]')),
        ],
      ),
    );
  }

  String? _tipoPrecioSeleccionadoOvejas;
  final TextEditingController _precioControllerOvejas = TextEditingController();

  Widget _campoDropdownOvejas() {
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
        value: _tipoPrecioSeleccionadoOvejas,
        onChanged: (value) {
          setState(() {
            _tipoPrecioSeleccionadoOvejas = value;
          });
        },
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _campoPrecioOvejas() {
    TextInputType tipoTeclado = TextInputType.number;
    String? Function(String?)? validador;
    int maxLength = 4;
    final TextEditingController controller = _precioControllerOvejas;
    List<TextInputFormatter>? inputFormatters;
    if (_tipoPrecioSeleccionadoOvejas == 'eur_unidad') {
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,4}$');
        if (!exp.hasMatch(value)) return 'MÃ¡ximo 4 cifras, sin decimales';
        return null;
      };
      tipoTeclado = TextInputType.number;
      maxLength = 4;
      inputFormatters = [FilteringTextInputFormatter.digitsOnly];
    } else if (_tipoPrecioSeleccionadoOvejas == 'eur_kg' ||
        _tipoPrecioSeleccionadoOvejas == 'eur_libra' ||
        _tipoPrecioSeleccionadoOvejas == 'eur_arroba') {
      validador = (value) {
        if (value == null || value.isEmpty) return 'El precio es obligatorio.';
        final exp = RegExp(r'^[0-9]{1,2}([\.,][0-9])?$');
        if (!exp.hasMatch(value)) return 'MÃ¡ximo 2 cifras y 1 decimal';
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
        enabled: _tipoPrecioSeleccionadoOvejas != null,
        validator: validador,
        maxLength: maxLength,
      ),
    );
  }

  Widget _campoFotosOvejas() {
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
                    _fotoBytesCacheOvejas[_fotoCacheKeyOvejas(xf)] = p.bytes;
                    pickedFiles.add(xf);
                  }
                } else {
                  pickedFiles = await _pickerOvejas.pickMultiImage();
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
              final int remaining = max - _fotosOvejas.length;
              if (remaining <= 0) {
                final loc = AppLocalizations.of(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(loc.t('errorMax10Photos'))),
                );
                return;
              }
              final List<XFile> newUnique = pickedFiles
                  .where((x) => !_fotosOvejas.any((e) => e.path == x.path || e.name == x.name))
                  .toList();
              final List<XFile> toAdd = newUnique.take(remaining).toList();
              final List<XFile> cacheable = <XFile>[];
              for (final file in toAdd) {
                try {
                  final key = _fotoCacheKeyOvejas(file);
                  _fotoBytesCacheOvejas[key] =
                      _fotoBytesCacheOvejas[key] ?? await file.readAsBytes();
                  cacheable.add(file);
                } catch (_) {
                  // Best effort: if caching fails, upload will try reading again.
                }
              }
              setState(() {
                _fotosOvejas.addAll(cacheable);
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
                  picked = await _pickerOvejas.pickVideo(
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
                  _videoOvejas = picked;
                  _videoBytesCacheOvejas = cachedBytes;
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
              'Fotos listas: ${_fotoBytesCacheOvejas.length}/${_fotosOvejas.length}\n'
              'Video listo: ${_videoOvejas == null ? 'no seleccionado' : (_videoBytesCacheOvejas != null ? 'si' : 'no')}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF004d26)),
            ),
          ),
          const SizedBox(height: 8),
          if (_fotosOvejas.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _fotosOvejas.asMap().entries.map((entry) {
                final int index = entry.key;
                final file = entry.value;
                final cachedBytes = _fotoBytesCacheOvejas[_fotoCacheKeyOvejas(file)];
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
                              final removed = _fotosOvejas.removeAt(index);
                              _fotoBytesCacheOvejas.remove(_fotoCacheKeyOvejas(removed));
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
          if (_videoOvejas != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.videocam, size: 20, color: Color(0xFF0288D1)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _videoOvejas!.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar video',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _videoOvejas = null;
                      _videoBytesCacheOvejas = null;
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
                    const Text('Vender ovejas',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Form(
                        key: _formKeyOvejas,
                        child: Column(
                          children: [
                            _campoDropdownOvejas(),
                            const SizedBox(height: 4),
                            _campoPrecioOvejas(),
                            const SizedBox(height: 4),
                            _campoTextoOvejas(
                              'Cantidad',
                              TextInputType.number,
                              maxLength: 3,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La cantidad es obligatoria.';
                                }
                                final exp = RegExp(r'^[0-9]{1,3}$');
                                if (!exp.hasMatch(value)) return 'MÃ¡ximo 3 cifras';
                                return null;
                              },
                              controller: _cantidadControllerOvejas,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOvejas(
                              'Peso medio (por animal)',
                              TextInputType.number,
                              unidad: _tipoPrecioSeleccionadoOvejas == 'eur_libra'
                                  ? 'libras'
                                  : _tipoPrecioSeleccionadoOvejas == 'eur_arroba'
                                      ? '@'
                                      : 'kg',
                              maxLength: 4,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'El peso medio es obligatorio.';
                                }
                                final exp = RegExp(r'^[0-9]{1,4}$');
                                if (!exp.hasMatch(value)) return 'MÃ¡ximo 4 cifras';
                                return null;
                              },
                              controller: _pesoMedioControllerOvejas,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOvejas(
                              'Raza',
                              TextInputType.text,
                              maxLength: 10,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La raza es obligatoria.';
                                }
                                final exp = RegExp(r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘]{1,10}$');
                                if (!exp.hasMatch(value)) return 'Solo letras, mÃ¡ximo 10';
                                return null;
                              },
                              controller: _razaControllerOvejas,
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOvejas(
                              'Edad (meses)',
                              TextInputType.number,
                              maxLength: 2,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'La edad es obligatoria.';
                                }
                                final exp = RegExp(r'^[0-9]{1,2}$');
                                if (!exp.hasMatch(value)) return 'MÃ¡ximo 2 cifras';
                                return null;
                              },
                              controller: _edadControllerOvejas,
                            ),
                            const SizedBox(height: 4),
                            _campoFormaPagoOvejas(),
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
                                      _fechaSalidaOvejas = picked;
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
                                        text: _fechaSalidaOvejas == null
                                            ? ''
                                            : '${_fechaSalidaOvejas!.day.toString().padLeft(2, '0')}/${_fechaSalidaOvejas!.month.toString().padLeft(2, '0')}/${_fechaSalidaOvejas!.year}'),
                                    readOnly: true,
                                    style: const TextStyle(fontSize: 14, height: 1.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _campoTextoOvejas(
                              'CÃ³digo Postal',
                              TextInputType.number,
                              maxLength: 5,
                              validator: (value) {
                                if (value == null || value.isEmpty) return null;
                                final exp = RegExp(r'^[0-9]{1,5}$');
                                if (!exp.hasMatch(value)) return 'MÃ¡ximo 5 cifras';
                                return null;
                              },
                              controller: _codigoPostalControllerOvejas,
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
                                          backgroundColor: _diferenciaRespuestaOvejas == 'si'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuestaOvejas == 'si'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuestaOvejas = 'si';
                                            _declaracionGuardadaOvejas = false;
                                          });
                                        },
                                        child: const Text('SÃ­'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _diferenciaRespuestaOvejas == 'no'
                                              ? const Color(0xFF004d26)
                                              : const Color(0xFFE3F2FD),
                                          foregroundColor: _diferenciaRespuestaOvejas == 'no'
                                              ? Colors.white
                                              : const Color(0xFF004d26),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _diferenciaRespuestaOvejas = 'no';
                                            _diferenciaControllerOvejas.clear();
                                            _declaracionGuardadaOvejas = false;
                                          });
                                        },
                                        child: const Text('No'),
                                      ),
                                    ],
                                  ),
                                  if (_diferenciaRespuestaOvejas == 'si') ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _diferenciaControllerOvejas,
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
                                        if (_declaracionGuardadaOvejas) {
                                          setState(() {
                                            _declaracionGuardadaOvejas = false;
                                          });
                                        }
                                      },
                                      inputFormatters: [
                                        // Bloquea cualquier dÃ­gito (0-9) incluso si se pega desde el portapapeles
                                        FilteringTextInputFormatter.deny(RegExp(r'[0-9]')),
                                        // Refuerza el lÃ­mite de longitud en tiempo real
                                        LengthLimitingTextInputFormatter(40),
                                      ],
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Debes describir la diferencia o defecto (solo letras)';
                                        }
                                        final exp = RegExp(
                                            r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘ ]{1,40}$');
                                        if (!exp.hasMatch(value)) {
                                          return 'Solo letras, sin nÃºmeros, mÃ¡ximo 40';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingDeclaracionOvejas ||
                                              _declaracionGuardadaOvejas ||
                                              _diferenciaControllerOvejas.text.trim().isEmpty
                                          ? null
                                          : () async {
                                              final descripcion =
                                                  _diferenciaControllerOvejas.text.trim();
                                              final exp = RegExp(
                                                  r'^[a-zA-ZÃ¡Ã©Ã­Ã³ÃºÃÃ‰ÃÃ“ÃšÃ¼ÃœÃ±Ã‘ ]{1,40}$');
                                              if (!exp.hasMatch(descripcion)) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        'Solo letras, sin nÃºmeros, mÃ¡ximo 40'),
                                                  ),
                                                );
                                                return;
                                              }
                                              setState(() {
                                                _isSavingDeclaracionOvejas = true;
                                              });
                                              await Future<void>.delayed(
                                                  const Duration(seconds: 2));
                                              setState(() {
                                                _isSavingDeclaracionOvejas = false;
                                                _declaracionGuardadaOvejas = true;
                                              });
                                              final loc = AppLocalizations.of(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                    content: Text(loc.t('declarationSavedOk'))),
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracionOvejas
                                            ? Colors.grey
                                            : _declaracionGuardadaOvejas
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracionOvejas
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardadaOvejas
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
                                  if (_diferenciaRespuestaOvejas == 'no') ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Declaro bajo mi responsabilidad que no se conoce defecto o diferencia en ningÃºn animal del grupo.',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 8),
                                    ElevatedButton(
                                      onPressed: _isSavingDeclaracionSinDefectoOvejas ||
                                              _declaracionGuardadaOvejas
                                          ? null
                                          : () async {
                                              setState(() {
                                                _isSavingDeclaracionSinDefectoOvejas = true;
                                              });
                                              await Future<void>.delayed(
                                                  const Duration(seconds: 2));
                                              setState(() {
                                                _isSavingDeclaracionSinDefectoOvejas = false;
                                                _declaracionGuardadaOvejas = true;
                                              });
                                              final loc = AppLocalizations.of(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                    content: Text(loc.t('declarationSavedOk'))),
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isSavingDeclaracionSinDefectoOvejas
                                            ? Colors.grey
                                            : _declaracionGuardadaOvejas
                                                ? Colors.blue
                                                : const Color(0xFF004d26),
                                        foregroundColor: Colors.white,
                                      ),
                                      child: _isSavingDeclaracionSinDefectoOvejas
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2, color: Colors.white))
                                          : _declaracionGuardadaOvejas
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
                            _campoFotosOvejas(),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _isSavingOfertaOvejas
                                  ? null
                                  : () async {
                                      final loc = AppLocalizations.of(context);
                                      final bilingual = context.isBi;
                                      String add(String key) =>
                                          bilingual ? AppLocalizations.bilingual(key) : loc.t(key);
                                      String errorMsg = '';
                                      if (_tipoPrecioSeleccionadoOvejas == null ||
                                          _tipoPrecioSeleccionadoOvejas!.isEmpty) {
                                        errorMsg += '${add('errorPriceTypeRequired')}\n';
                                      }
                                      if (_precioControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorPriceRequired')}\n';
                                      }
                                      if (_cantidadControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorQuantityRequired')}\n';
                                      }
                                      if (_pesoMedioControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorAvgWeightRequired')}\n';
                                      }
                                      if (_razaControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorBreedRequired')}\n';
                                      }
                                      if (_edadControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorAgeRequired')}\n';
                                      }
                                      if (_formaPagoSeleccionadaOvejas == null ||
                                          _formaPagoSeleccionadaOvejas!.isEmpty) {
                                        errorMsg += '${add('errorPaymentFormRequired')}\n';
                                      }
                                      if (_fechaSalidaOvejas == null) {
                                        errorMsg += '${add('errorExitDateRequired')}\n';
                                      }
                                      if (_codigoPostalControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorPostalCodeRequired')}\n';
                                      }
                                      if (_diferenciaRespuestaOvejas == null ||
                                          _diferenciaRespuestaOvejas!.isEmpty) {
                                        errorMsg += '${add('errorDefectChoiceRequired')}\n';
                                      }
                                      if (_diferenciaRespuestaOvejas == 'si' &&
                                          _diferenciaControllerOvejas.text.isEmpty) {
                                        errorMsg += '${add('errorDefectDescriptionRequired')}\n';
                                      }
                                      if (_fotosOvejas.length < 2) {
                                        errorMsg += '${add('errorAtLeast2Photos')}\n';
                                      }
                                      if (_fotosOvejas.length > 10) {
                                        errorMsg += '${add('errorMax10Photos')}\n';
                                      }
                                      if (errorMsg.isNotEmpty ||
                                          !(_formKeyOvejas.currentState?.validate() ?? false)) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(SnackBar(content: Text(errorMsg.trim())));
                                        return;
                                      }
                                      setState(() {
                                        _isSavingOfertaOvejas = true;
                                        _uploadProgressOvejas = 0.0;
                                      });
                                      final List<String> uploadedUrls = [];
                                      try {
                                        final user = FirebaseAuth.instance.currentUser;
                                        if (user == null) throw 'Usuario no autenticado';
                                        final docRef = FirebaseFirestore.instance
                                            .collection('ovejas_ofertas')
                                            .doc();
                                        final offerId = docRef.id;
                                        for (int i = 0; i < _fotosOvejas.length; i++) {
                                          final file = _fotosOvejas[i];
                                          final ref = FirebaseStorage.instance.ref().child(
                                              'users/${user.uid}/offers/ovejas/$offerId/photos/$i.jpg');
                                          try {
                                            final raw =
                                                _fotoBytesCacheOvejas[_fotoCacheKeyOvejas(file)];
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
                                              _uploadProgressOvejas = (i + 1) / _fotosOvejas.length;
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
                                              _isSavingOfertaOvejas = false;
                                              _uploadProgressOvejas = 0.0;
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
                                        if (_videoOvejas != null) {
                                          try {
                                            final refVideo = FirebaseStorage.instance.ref().child(
                                                'users/${user.uid}/offers/ovejas/$offerId/video.mp4');
                                            final vbytes = _videoBytesCacheOvejas ??
                                                await _videoOvejas!.readAsBytes();
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
                                        final oferta = OvejaOferta(
                                          tipoPrecio: _tipoPrecioSeleccionadoOvejas ?? '',
                                          precio: _precioControllerOvejas.text.replaceAll(',', '.'),
                                          cantidad: _cantidadControllerOvejas.text,
                                          pesoMedio: _pesoMedioControllerOvejas.text,
                                          raza: _razaControllerOvejas.text,
                                          edadMeses: _edadControllerOvejas.text,
                                          formaPago: _formaPagoSeleccionadaOvejas ?? '',
                                          fechaSalida: _fechaSalidaOvejas == null
                                              ? ''
                                              : '${_fechaSalidaOvejas!.year}-${_fechaSalidaOvejas!.month.toString().padLeft(2, '0')}-${_fechaSalidaOvejas!.day.toString().padLeft(2, '0')}',
                                          codigoPostal: _codigoPostalControllerOvejas.text,
                                          diferenciaRespuesta: _diferenciaRespuestaOvejas ?? '',
                                          diferenciaDescripcion: _diferenciaRespuestaOvejas == 'si'
                                              ? _diferenciaControllerOvejas.text
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
                                          _isSavingOfertaOvejas = false;
                                          _uploadProgressOvejas = 0.0;
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
                                          _isSavingOfertaOvejas = false;
                                          _uploadProgressOvejas = 0.0;
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
                                    _isSavingOfertaOvejas ? Colors.grey : const Color(0xFF004d26),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 40),
                                shape:
                                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: _isSavingOfertaOvejas
                                  ? Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                                value: _uploadProgressOvejas > 0
                                                    ? _uploadProgressOvejas
                                                    : null)),
                                        if (_uploadProgressOvejas > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 8.0),
                                            child: Text(
                                                AppLocalizations.of(context)
                                                    .tf('uploadingPhotosProgress', {
                                                  'percent': (_uploadProgressOvejas * 100)
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
