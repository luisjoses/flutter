import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';

class TratoDetalleScreen extends StatefulWidget {
  const TratoDetalleScreen({
    super.key,
    required this.docId,
    required this.collection,
    required this.data,
    required this.role,
    required this.isClosed,
  });

  final String docId;
  final String collection;
  final Map<String, dynamic> data;
  final String role;
  final bool isClosed;

  @override
  State<TratoDetalleScreen> createState() => _TratoDetalleScreenState();
}

class _TratoDetalleScreenState extends State<TratoDetalleScreen> {
  bool _isAccepting = false;
  bool _isCancelling = false;

  String _s(dynamic v) => (v ?? '').toString();

  DateTime? _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  bool _isDealClosed(Map<String, dynamic> d) {
    return d['vendido'] == true ||
        (d['aceptadoComprador'] == true && d['aceptadoVendedor'] == true) ||
        _parseDate(d['fechaCierreTrato']) != null;
  }

  String _resolveSellerUid(Map<String, dynamic> data) {
    return (data['vendedor'] ?? data['vendedorId'] ?? data['vendedorUid'] ?? '').toString().trim();
  }

  String _resolveBuyerUid(Map<String, dynamic> data) {
    return (data['comprador'] ?? data['compradorId'] ?? data['compradorUid'] ?? '')
        .toString()
        .trim();
  }

  double _parsePositiveDouble(dynamic raw) {
    final value = _s(raw).trim().replaceAll(',', '.');
    if (value.isEmpty) return 0;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return 0;
    return parsed;
  }

  int _parsePositiveInt(dynamic raw, {int fallback = 1}) {
    final value = _s(raw).trim().replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  int _timestampToMillis(dynamic raw) {
    if (raw is Timestamp) return raw.toDate().millisecondsSinceEpoch;
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    if (raw is num) return raw.toInt();
    if (raw is String && raw.trim().isNotEmpty) {
      final parsedInt = int.tryParse(raw.trim());
      if (parsedInt != null) return parsedInt;
      final parsedDt = DateTime.tryParse(raw.trim());
      if (parsedDt != null) return parsedDt.millisecondsSinceEpoch;
    }
    return 0;
  }

  bool _usaPesoParaComision(String tipoPrecio) {
    final tipo = tipoPrecio.toLowerCase().trim();
    return tipo.contains('kg') ||
        tipo.contains('libra') ||
        tipo.contains('arroba') ||
        tipo.contains('@');
  }

  String _unidadPesoDesdeTipoPrecio(String tipoPrecio) {
    final tipo = tipoPrecio.toLowerCase().trim();
    if (tipo.contains('kg')) return 'kg';
    if (tipo.contains('libra')) return 'libra';
    if (tipo.contains('arroba') || tipo.contains('@')) return 'arroba';
    if (tipo.contains('unidad') || tipo.contains('und')) return 'unidad';
    return '';
  }

  double _resolvePesoOfertaReferencia(Map<String, dynamic> offerData) {
    const candidateKeys = <String>[
      'pesoMedio',
      'peso_medio',
      'pesoPromedio',
      'pesoAnimal',
      'peso',
    ];
    for (final key in candidateKeys) {
      final parsed = _parsePositiveDouble(offerData[key]);
      if (parsed > 0) return parsed;
    }
    return 0;
  }

  Future<Map<String, dynamic>?> _getUltimaContraoferta() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('mensajes')
          .where('ofertaId', isEqualTo: widget.docId)
          .where('tipo', isEqualTo: 'contraoferta')
          .get();
      if (snap.docs.isEmpty) return null;
      final lista = snap.docs.map((doc) => doc.data()).toList();
      lista.sort(
        (a, b) => _timestampToMillis(b['timestamp']).compareTo(_timestampToMillis(a['timestamp'])),
      );
      return lista.first;
    } catch (_) {
      return null;
    }
  }

  String _formatMoney(double amount) => amount.toStringAsFixed(2);

  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  String _penalizacionTipoLabel(String raw) {
    switch (raw.trim()) {
      case 'no_paga':
        return 'No pagar';
      case 'descuento':
      default:
        return 'Descuento';
    }
  }

  List<String> _penalizacionResumen(dynamic raw) {
    if (raw is! Map) return const <String>[];
    const labels = <String, String>{
      'minimoIndividual': 'Minimo individual',
      'minimoColectivo': 'Minimo colectivo',
      'maximoIndividual': 'Maximo individual',
      'maximoColectivo': 'Maximo colectivo',
      'defectoAnimal': 'Animal defectuoso',
    };
    final lines = <String>[];
    for (final entry in labels.entries) {
      final item = raw[entry.key];
      if (item is! Map || item['activa'] != true) continue;
      final tipo = _penalizacionTipoLabel((item['tipo'] ?? '').toString());
      if (entry.key == 'defectoAnimal') {
        final descripcion = _s(item['descripcion']).trim();
        final valor = _s(item['valor']).trim();
        final parts = <String>[];
        if (descripcion.isNotEmpty) parts.add(descripcion);
        if (tipo == 'No pagar') {
          parts.add('no se paga');
        } else if (valor.isNotEmpty) {
          parts.add('descuento $valor');
        }
        lines.add('${entry.value}: ${parts.join(' | ')}');
        continue;
      }
      final umbral = _s(item['umbral']).trim();
      final valor = _s(item['valor']).trim();
      final parts = <String>[];
      if (umbral.isNotEmpty) parts.add('umbral $umbral');
      if (tipo == 'No pagar') {
        parts.add('no se paga');
      } else if (valor.isNotEmpty) {
        parts.add('descuento $valor');
      }
      lines.add('${entry.value}: ${parts.join(' | ')}');
    }
    return lines;
  }

  String _resolveCounterpartyRole(Map<String, dynamic> data) {
    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final vendedorUid = _resolveSellerUid(data);
    final compradorUid = _resolveBuyerUid(data);

    if (miUid.isNotEmpty) {
      if (miUid == vendedorUid) return 'comprador';
      if (miUid == compradorUid) return 'vendedor';
    }

    if (widget.role == 'vendedor') return 'comprador';
    if (widget.role == 'comprador') return 'vendedor';
    return 'contraparte';
  }

  bool _isCounterpartyContactExpired(Map<String, dynamic> data) {
    final closedAt = _parseDate(data['fechaCierreTrato']);
    if (closedAt == null) return false;
    final expiresAt = closedAt.add(const Duration(days: 15));
    return DateTime.now().isAfter(expiresAt);
  }

  Future<Map<String, String>> _loadCounterpartyContact(Map<String, dynamic> offerData) async {
    if (_isCounterpartyContactExpired(offerData)) {
      return <String, String>{
        'role': _resolveCounterpartyRole(offerData),
        'nombre': 'No disponible',
        'telefono': 'No disponible',
      };
    }

    final callable = FirebaseFunctions.instance.httpsCallable('getDealCounterpartyContact');
    final result = await callable.call<Map<String, dynamic>>(<String, dynamic>{
      'ofertaId': widget.docId,
      'coleccion': widget.collection,
    });

    final data = result.data;
    return <String, String>{
      'role': _s(data['role']).trim(),
      'nombre': _s(data['nombre']).trim().isEmpty ? 'Sin nombre' : _s(data['nombre']).trim(),
      'telefono':
          _s(data['telefono']).trim().isEmpty ? 'No disponible' : _s(data['telefono']).trim(),
    };
  }

  String _normalizeDialPhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed == 'No disponible') return '';
    final chars = trimmed.split('');
    final b = StringBuffer();
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      final isDigit = RegExp(r'[0-9]').hasMatch(c);
      if (isDigit || (c == '+' && b.isEmpty)) {
        b.write(c);
      }
    }
    return b.toString();
  }

  Future<void> _copyPhone(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty || clean == 'No disponible') return;
    await Clipboard.setData(ClipboardData(text: clean));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telefono copiado')),
    );
  }

  Future<void> _callPhone(String phone) async {
    final dial = _normalizeDialPhone(phone);
    if (dial.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: dial);
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el telefono')),
      );
    }
  }

  Widget _buildCounterpartyPhoneCard({
    required String title,
    required Map<String, String> data,
  }) {
    final phone = data['telefono'] ?? 'No disponible';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(data['nombre'] ?? 'Sin nombre'),
          Text('Telefono: $phone'),
          if (phone != 'No disponible' && phone.trim().isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => _callPhone(phone),
                  icon: const Icon(Icons.call, size: 18),
                  label: const Text('Llamar'),
                ),
                TextButton.icon(
                  onPressed: () => _copyPhone(phone),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copiar'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _sendContractByEmail(
    BuildContext context,
    AppLocalizations loc,
    bool bilingual,
  ) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  bilingual
                      ? AppLocalizations.bilingual('sendingContract')
                      : loc.t('sendingContract'),
                ),
              ),
            ],
          ),
        );
      },
    );

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendDealContractEmail');
      final HttpsCallableResult<Map<String, dynamic>> result =
          await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'ofertaId': widget.docId,
        'coleccion': widget.collection,
      });

      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      final Map<String, dynamic> dataMap = result.data;
      final sentTo = (dataMap['sentTo'] ?? 0).toString();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bilingual
                ? AppLocalizations.bilingual('contractEmailSentCount').replaceAll('{count}', sentTo)
                : loc.tf('contractEmailSentCount', <String, String>{'count': sentTo}),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
      final base = e.message ??
          (bilingual ? AppLocalizations.bilingual('errorGeneric') : loc.t('errorGeneric'));
      final detail = e.details == null ? '' : ' (${e.details})';
      final message = '[${e.code}] $base$detail';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bilingual
                ? AppLocalizations.bilingual('contractEmailError').replaceAll('{error}', message)
                : loc.tf('contractEmailError', <String, String>{'error': message}),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bilingual
                ? AppLocalizations.bilingual('contractEmailError')
                    .replaceAll('{error}', e.toString())
                : loc.tf('contractEmailError', <String, String>{'error': e.toString()}),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _cancelDeal(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'âš ï¸ Â¡ATENCIÃ“N!\nPerderÃ¡s la comisiÃ³n pagada',
          style: TextStyle(
            color: Colors.red,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: const Text(
          'Si cancelas ahora, PERDERÃS la comisiÃ³n que ya has pagado. Esta cantidad NO serÃ¡ reembolsada en ningÃºn caso.\n\nÂ¿Seguro que quieres cancelar el trato?',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('SÃ­, cancelar (perderÃ© mi comisiÃ³n)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      final ofertaRef = FirebaseFirestore.instance.collection(widget.collection).doc(widget.docId);
      await ofertaRef.update({
        'enTrato': false,
        'aceptadoComprador': false,
        'aceptadoVendedor': false,
        'pagadoComprador': false,
        'pagadoVendedor': false,
        'comprador': FieldValue.delete(),
        'ventanaTratoInicio': FieldValue.delete(),
        'ventanaTratoExpira': FieldValue.delete(),
        'fechaCierreTrato': FieldValue.delete(),
        'precioFinal': FieldValue.delete(),
        'cantidadFinal': FieldValue.delete(),
        'cantidadSolicitadaComprador': FieldValue.delete(),
        'cantidadSolicitadaPorComprador': FieldValue.delete(),
        'cantidadSolicitadaEstado': FieldValue.delete(),
        'cantidadSolicitadaAt': FieldValue.delete(),
        'formaPagoFinal': FieldValue.delete(),
        'fechaSalidaFinal': FieldValue.delete(),
        'penalizacionPropuesta': FieldValue.delete(),
        'penalizacionFinal': FieldValue.delete(),
        'penalizacionEstado': FieldValue.delete(),
        'penalizacionPropuestaPor': FieldValue.delete(),
        'penalizacionPropuestaAt': FieldValue.delete(),
        'penalizacionRespuestaAt': FieldValue.delete(),
        'bloqueadaHasta': FieldValue.delete(),
        'bloqueadaPor': FieldValue.delete(),
        'bloqueadaPara': FieldValue.delete(),
        'expirado': false,
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cancelar: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _acceptDeal(
    BuildContext context,
    AppLocalizations loc,
    bool bilingual,
    Map<String, dynamic> offerData,
  ) async {
    if (_isAccepting) return;

    final user = FirebaseAuth.instance.currentUser;
    final miUid = user?.uid ?? '';
    if (miUid.isEmpty) return;

    final vendedorUid = _resolveSellerUid(offerData);
    final compradorUid = _resolveBuyerUid(offerData);

    final esVendedor = vendedorUid.isNotEmpty && miUid == vendedorUid;
    final esComprador = compradorUid.isNotEmpty && miUid == compradorUid;
    if (!esVendedor && !esComprador) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('errorGeneric'))),
      );
      return;
    }

    final penalizacionEstado = _s(offerData['penalizacionEstado']).trim();
    if (esVendedor && penalizacionEstado == 'pendiente') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resuelve antes la penalizacion propuesta por el comprador.'),
        ),
      );
      return;
    }

    final ultimaContra = await _getUltimaContraoferta();
    if (ultimaContra != null && _s(ultimaContra['remitenteUid']) == miUid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes aceptar la ultima contraoferta enviada por la contraparte.'),
        ),
      );
      return;
    }

    final ofertaRef = FirebaseFirestore.instance.collection(widget.collection).doc(widget.docId);
    final liveOfferSnap = await ofertaRef.get();
    final liveOfferData = liveOfferSnap.data() ?? offerData;

    final precioStr = _s(liveOfferData['precioFinal']).isNotEmpty
        ? _s(liveOfferData['precioFinal'])
        : _s(liveOfferData['precio']);
    final cantidadRaw = _s(liveOfferData['cantidadFinal']).isNotEmpty
        ? _s(liveOfferData['cantidadFinal'])
        : _s(liveOfferData['cantidad']);
    final cantidadFinal = _parsePositiveInt(cantidadRaw, fallback: 1);
    final precioDouble = double.tryParse(precioStr.replaceAll(',', '.')) ?? 0;
    final tipoPrecioFinal = _s(liveOfferData['tipoPrecio']).isNotEmpty
        ? _s(liveOfferData['tipoPrecio'])
        : _s(offerData['tipoPrecio']);
    final pesoOferta = _resolvePesoOfertaReferencia(liveOfferData);
    final usaPeso = _usaPesoParaComision(tipoPrecioFinal);
    final factorPesoComision = usaPeso ? (pesoOferta > 0 ? pesoOferta : 1) : 1;
    final totalNegociado = precioDouble * cantidadFinal * factorPesoComision;
    final double comision = (totalNegociado * 0.0015).clamp(1.0, double.infinity).toDouble();
    final comisionFmt = _formatMoney(comision);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.t('payCommission')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.tf('commissionAmount', <String, String>{'amount': comisionFmt})),
            if (usaPeso)
              Text(
                'Base: ${precioDouble.toStringAsFixed(2)} x $cantidadFinal x ${factorPesoComision.toStringAsFixed(2)} ${_unidadPesoDesdeTipoPrecio(tipoPrecioFinal)}',
              ),
            const SizedBox(height: 8),
            Text(loc.t('commissionPayment')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.t('accept')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isAccepting = true);
    try {
      final snapBefore = await ofertaRef.get();
      final dataBefore = snapBefore.data() ?? offerData;

      final yaPagadoComprador = dataBefore['pagadoComprador'] == true;
      final yaPagadoVendedor = dataBefore['pagadoVendedor'] == true;
      final yaAceptadoComprador = dataBefore['aceptadoComprador'] == true;
      final yaAceptadoVendedor = dataBefore['aceptadoVendedor'] == true;

      final miRol = esVendedor ? 'vendedor' : 'comprador';
      final otroRol = miRol == 'vendedor' ? 'comprador' : 'vendedor';

      final formaPagoFinal = _s(dataBefore['formaPagoFinal']).isNotEmpty
          ? _s(dataBefore['formaPagoFinal'])
          : _s(dataBefore['formaPago']);
      final fechaSalidaFinal = _s(dataBefore['fechaSalidaFinal']).isNotEmpty
          ? _s(dataBefore['fechaSalidaFinal'])
          : _s(dataBefore['fecha']);

      final updates = <String, dynamic>{
        'enTrato': true,
        'pagado${_cap(miRol)}': true,
        'aceptado${_cap(miRol)}': true,
        'precioFinal': precioStr,
        'cantidadFinal': cantidadFinal.toString(),
        'tipoPrecioFinal': tipoPrecioFinal,
        if (pesoOferta > 0) 'pesoMedioReferenciaComision': pesoOferta.toString(),
        if (_unidadPesoDesdeTipoPrecio(tipoPrecioFinal).isNotEmpty)
          'unidadPesoReferenciaComision': _unidadPesoDesdeTipoPrecio(tipoPrecioFinal),
        'totalNegociadoBaseComision': _formatMoney(totalNegociado),
        'comisionCalculada': comisionFmt,
        'comisionRate': 0.0015,
        if (ultimaContra != null) 'contraofertaAceptadaDeUid': _s(ultimaContra['remitenteUid']),
        if (ultimaContra != null && ultimaContra['timestamp'] != null)
          'contraofertaAceptadaAt': ultimaContra['timestamp'],
        'formaPagoFinal': formaPagoFinal,
        'fechaSalidaFinal': fechaSalidaFinal,
      };
      if (dataBefore['penalizacionFinal'] is Map) {
        updates['penalizacionFinal'] = dataBefore['penalizacionFinal'];
      }

      if (miRol == 'comprador') {
        updates['comprador'] = miUid;
      }

      final ahora = DateTime.now();
      final otroPago = otroRol == 'comprador' ? yaPagadoComprador : yaPagadoVendedor;
      final otroAcepto = otroRol == 'comprador' ? yaAceptadoComprador : yaAceptadoVendedor;
      final cierrePrevio = _isDealClosed(dataBefore);
      final cerrarTrato = otroPago || otroAcepto || cierrePrevio;

      if (!cerrarTrato) {
        updates['ventanaTratoInicio'] = ahora.toIso8601String();
        updates['ventanaTratoExpira'] = ahora.add(const Duration(hours: 24)).toIso8601String();
        updates['fechaCierreTrato'] = null;
        updates['expirado'] = false;
      } else {
        updates['aceptadoComprador'] = true;
        updates['aceptadoVendedor'] = true;
        updates['pagadoComprador'] = true;
        updates['pagadoVendedor'] = true;
        updates['vendido'] = true;
        updates['fechaCierreTrato'] = ahora.toIso8601String();
        updates['ventanaTratoInicio'] = FieldValue.delete();
        updates['ventanaTratoExpira'] = FieldValue.delete();
        updates['bloqueadaHasta'] = FieldValue.delete();
        updates['bloqueadaPor'] = FieldValue.delete();
        updates['bloqueadaPara'] = FieldValue.delete();
        updates['expirado'] = false;
      }

      await ofertaRef.set(updates, SetOptions(merge: true));

      final otroUid = miRol == 'vendedor' ? compradorUid : vendedorUid;
      if (otroUid.isNotEmpty) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendOfferPush');
        await callable.call<Map<String, dynamic>>(<String, dynamic>{
          'targetUid': otroUid,
          'ofertaId': widget.docId,
          'tipo': cerrarTrato ? 'trato_cerrado' : 'oferta_aceptada',
          'title': cerrarTrato ? loc.t('dealClosed') : loc.t('dealPending'),
          'body': cerrarTrato ? loc.t('dealClosedMsg') : loc.t('dealPendingMsg'),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cerrarTrato
              ? (bilingual ? AppLocalizations.bilingual('dealClosed') : loc.t('dealClosed'))
              : (bilingual ? AppLocalizations.bilingual('dealPending') : loc.t('dealPending'))),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bilingual
                ? AppLocalizations.bilingual('contractEmailError')
                    .replaceAll('{error}', e.toString())
                : loc.tf('contractEmailError', <String, String>{'error': e.toString()}),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final bilingual = MyApp.of(context)?.bilingualMode ?? false;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF004d26),
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection(widget.collection).doc(widget.docId).snapshots(),
        builder: (context, snapshot) {
          final offerData = snapshot.data?.data() ?? widget.data;

          final raza = _s(offerData['raza']);
          final cantidad = _s(offerData['cantidadFinal']).isNotEmpty
              ? _s(offerData['cantidadFinal'])
              : _s(offerData['cantidad']);
          final descripcion = _s(offerData['descripcionAnimales']).isNotEmpty
              ? _s(offerData['descripcionAnimales'])
              : (_s(offerData['descripcion']).isNotEmpty
                  ? _s(offerData['descripcion'])
                  : _s(offerData['detalles']));
          final tipoPrecio = _s(offerData['tipoPrecio']).replaceAll('eur_', 'â‚¬/');
          final precio = _s(offerData['precioFinal']).isNotEmpty
              ? _s(offerData['precioFinal'])
              : _s(offerData['precio']);
          final formaPago = _s(offerData['formaPagoFinal']).isNotEmpty
              ? _s(offerData['formaPagoFinal'])
              : _s(offerData['formaPago']);
          final fecha = _s(offerData['fechaSalidaFinal']).isNotEmpty
              ? _s(offerData['fechaSalidaFinal'])
              : _s(offerData['fecha']);
          final penalizacionLineas = _penalizacionResumen(offerData['penalizacionFinal']);

          final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
          final vendedorUid = _resolveSellerUid(offerData);
          final compradorUid = _resolveBuyerUid(offerData);
          final soyVendedor = vendedorUid.isNotEmpty && miUid == vendedorUid;
          final soyComprador = compradorUid.isNotEmpty && miUid == compradorUid;

          final tratoCerrado = _isDealClosed(offerData);
          final expirado = offerData['expirado'] == true;
          final yaAcepte = soyVendedor
              ? offerData['aceptadoVendedor'] == true
              : (soyComprador && offerData['aceptadoComprador'] == true);

          final otroAcepto = soyVendedor
              ? offerData['aceptadoComprador'] == true
              : (soyComprador && offerData['aceptadoVendedor'] == true);
          final canAccept =
              (soyVendedor || soyComprador) && !tratoCerrado && !expirado && !yaAcepte;
          final canCancel = yaAcepte && !tratoCerrado && !expirado && (soyVendedor || soyComprador);
          final canSendContract = tratoCerrado;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Text(
                  bilingual ? AppLocalizations.bilingual('reviewDeal') : loc.t('reviewDeal'),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tratoCerrado
                            ? (bilingual
                                ? AppLocalizations.bilingual('dealClosed')
                                : loc.t('dealClosed'))
                            : (bilingual
                                ? AppLocalizations.bilingual('dealPending')
                                : loc.t('dealPending')),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text('Rol: ${widget.role}'),
                      Text('Coleccion: ${widget.collection}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${bilingual ? AppLocalizations.bilingual('race') : loc.t('race')}: $raza'),
                      const SizedBox(height: 6),
                      Text(
                          '${bilingual ? AppLocalizations.bilingual('quantity') : loc.t('quantity')}: $cantidad'),
                      if (descripcion.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                            '${bilingual ? AppLocalizations.bilingual('description') : loc.t('description')}: $descripcion'),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        '${bilingual ? AppLocalizations.bilingual('price') : loc.t('price')}: $precio $tipoPrecio',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                          '${bilingual ? AppLocalizations.bilingual('paymentMethod') : loc.t('paymentMethod')}: $formaPago'),
                      const SizedBox(height: 6),
                      Text(
                          '${bilingual ? AppLocalizations.bilingual('estimatedExitDate') : loc.t('estimatedExitDate')}: $fecha'),
                      if (penalizacionLineas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        const Text(
                          'Penalizacion acordada:',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        for (final line in penalizacionLineas) ...[
                          Text('â€¢ $line'),
                          const SizedBox(height: 4),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (canAccept)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isAccepting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_circle_outline),
                    onPressed:
                        _isAccepting ? null : () => _acceptDeal(context, loc, bilingual, offerData),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004d26),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    label: Text(
                      otroAcepto
                          ? 'Cerrar trato'
                          : (bilingual
                              ? AppLocalizations.bilingual('acceptDeal')
                              : loc.t('acceptDeal')),
                    ),
                  ),
                ),
              if (canAccept) const SizedBox(height: 10),
              if (canCancel) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Esperando que la otra parte cierre el trato...',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _isCancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cancel_outlined),
                    onPressed: _isCancelling ? null : () => _cancelDeal(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    label: const Text('Cancelar trato'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (canSendContract)
                FutureBuilder<Map<String, String>>(
                  future: _loadCounterpartyContact(offerData),
                  builder: (context, contactsSnapshot) {
                    final contact = contactsSnapshot.data ?? <String, String>{};
                    final counterpartyRole = contact['role'];
                    final counterpartyTitle = counterpartyRole == 'comprador'
                        ? 'Telefono del comprador'
                        : (counterpartyRole == 'vendedor'
                            ? 'Telefono del vendedor'
                            : (soyVendedor
                                ? 'Telefono del comprador'
                                : (soyComprador
                                    ? 'Telefono del vendedor'
                                    : 'Telefono de la contraparte')));

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isLoading =
                            contactsSnapshot.connectionState == ConnectionState.waiting;
                        final hasError = contactsSnapshot.hasError;
                        final button = SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.email_outlined),
                            onPressed: () => _sendContractByEmail(context, loc, bilingual),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004d26),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            label: Text(
                              bilingual
                                  ? AppLocalizations.bilingual('sendContractByEmail')
                                  : loc.t('sendContractByEmail'),
                            ),
                          ),
                        );

                        final phoneCard = isLoading
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.green.shade200),
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : hasError
                                ? Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          counterpartyTitle,
                                          style: const TextStyle(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(_s(contactsSnapshot.error)),
                                      ],
                                    ),
                                  )
                                : _buildCounterpartyPhoneCard(
                                    title: counterpartyTitle,
                                    data: contact,
                                  );

                        if (constraints.maxWidth < 720) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              button,
                              const SizedBox(height: 10),
                              phoneCard,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 3, child: button),
                            const SizedBox(width: 12),
                            Expanded(flex: 2, child: phoneCard),
                          ],
                        );
                      },
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
