import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';

const List<String> _penalizacionRuleKeys = <String>[
  'minimoIndividual',
  'minimoColectivo',
  'maximoIndividual',
  'maximoColectivo',
  'defectoAnimal',
];

const List<String> _penalizacionMinimoKeys = <String>[
  'minimoIndividual',
  'minimoColectivo',
];

const List<String> _penalizacionMaximoKeys = <String>[
  'maximoIndividual',
  'maximoColectivo',
];

const Map<String, String> _penalizacionRuleLabels = <String, String>{
  'minimoIndividual': 'Minimo individual',
  'minimoColectivo': 'Minimo colectivo',
  'maximoIndividual': 'Maximo individual',
  'maximoColectivo': 'Maximo colectivo',
  'defectoAnimal': 'Animal defectuoso',
};

const Map<String, String> _penalizacionTypeLabels = <String, String>{
  'descuento': 'Descuento',
  'no_paga': 'No pagar',
};

class ChatContraofertaScreen extends StatefulWidget {
  final String chatId;
  final String counterpartUid;
  final String ofertaId;
  final String coleccion;
  final String vendedorId;
  final String tipoPrecio;
  final String formaPago;
  final String fechaSalida;
  final double precioInicial;
  final String raza;
  final String cantidad;

  const ChatContraofertaScreen({
    Key? key,
    this.chatId = '',
    this.counterpartUid = '',
    required this.ofertaId,
    this.coleccion = 'vacas_ofertas',
    required this.vendedorId,
    required this.tipoPrecio,
    required this.formaPago,
    required this.fechaSalida,
    required this.precioInicial,
    required this.raza,
    required this.cantidad,
  }) : super(key: key);

  @override
  State<ChatContraofertaScreen> createState() => _ChatContraofertaScreenState();
}

class _ChatContraofertaScreenState extends State<ChatContraofertaScreen> {
  static const List<String> _coleccionesOferta = <String>[
    'vacas_ofertas',
    'cabras_ofertas',
    'cerdos_ofertas',
    'ovejas_ofertas',
    'otros_ofertas',
  ];

  final ScrollController _scrollController = ScrollController();
  String? _chatId; // id del chat (oferta + pareja comprador-vendedor)
  String? _counterpartUid;
  List<Map<String, dynamic>> _mensajesCache = <Map<String, dynamic>>[];
  late String _coleccionActiva;
  // Campos de propuesta actuales (el diÃ¡logo fue eliminado; no se requiere estado adicional)
  bool _loadingSend = false;
  bool _sendInProgress = false;
  String? _lastEnsureChatError;
  bool get _isSending => _loadingSend || _sendInProgress;

  // Campos de negociaciÃ³n en pantalla
  late final TextEditingController _precioFormCtrl;
  late final TextEditingController _cantidadFormCtrl;
  String _formaPagoForm = 'transferencia';
  DateTime? _fechaForm;

  @override
  void initState() {
    super.initState();
    _coleccionActiva =
        _coleccionesOferta.contains(widget.coleccion) ? widget.coleccion : 'vacas_ofertas';
    // Validar que la navegaciÃ³n llegÃ³ con datos completos desde "Comprar â†’ Oferta â†’ Contraoferta"
    if (!_validRouteArgs()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('startFromOfferRoute'))),
        );
        Navigator.pop(context);
      });
      return;
    }
    // Inicializar _chatId de inmediato si viene informado para que el StreamBuilder
    // de mensajes arranque sin esperar la llamada asÃ­ncrona de _asegurarChat.
    final fixedChatId = widget.chatId.trim();
    if (fixedChatId.isNotEmpty) {
      _chatId = fixedChatId;
    }
    final fixedCounterpartUid = widget.counterpartUid.trim();
    if (fixedCounterpartUid.isNotEmpty) {
      _counterpartUid = fixedCounterpartUid;
    }
    _asegurarChat();
    _precioFormCtrl = TextEditingController(
        text: widget.precioInicial > 0 ? widget.precioInicial.toString() : '');
    _cantidadFormCtrl = TextEditingController();
    // Asegurar que el valor inicial estÃ© permitido
    _formaPagoForm = (widget.formaPago.isNotEmpty &&
            _formasPagoPermitidas.contains(widget.formaPago.toLowerCase()))
        ? widget.formaPago.toLowerCase()
        : 'transferencia';
    _fechaForm = _parseDate(widget.fechaSalida);
  }

  String _composePairChatId(String ofertaId, String uidA, String uidB) {
    final ids = <String>[uidA.trim(), uidB.trim()]..sort();
    return '${ofertaId.trim()}__${ids[0]}__${ids[1]}';
  }

  Future<String> _ensurePairChatViaCallable({
    required String ofertaId,
    required String vendedorId,
  }) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('ensurePairChat');
      final resp = await callable.call<Map<String, dynamic>>({
        'ofertaId': ofertaId,
        'coleccion': _coleccionActiva,
        'vendedorId': vendedorId,
        if ((_counterpartUid ?? '').trim().isNotEmpty) 'counterpartUid': _counterpartUid!.trim(),
      });
      final data = resp.data;
      final chatId = (data['chatId'] ?? '').toString().trim();
      final resolvedCollection = (data['coleccion'] ?? '').toString().trim();
      if (resolvedCollection.isNotEmpty && _coleccionesOferta.contains(resolvedCollection)) {
        _coleccionActiva = resolvedCollection;
      }
      _lastEnsureChatError = null;
      return chatId;
    } catch (e) {
      _lastEnsureChatError = e.toString();
      return '';
    }
  }

  Future<void> enviarContraoferta(Map<String, dynamic> contraoferta,
      {bool retrying = false}) async {
    if (_sendInProgress) return;
    if (mounted) {
      setState(() {
        _sendInProgress = true;
        _loadingSend = true;
      });
    } else {
      _sendInProgress = true;
      _loadingSend = true;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      final miUid = user?.uid;
      if (miUid == null) return;

      final secondsLeft = await _secondsUntilNextOwnCounteroffer(miUid);
      if (secondsLeft > 0) {
        if (mounted) {
          final loc = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.tf('counterofferCooldown', {'seconds': '$secondsLeft'}))),
          );
        }
        return;
      }

      await _resetExpiredOfferStateIfNeeded();
      if (!await _puedeEscribirContraoferta(miUid)) {
        if (mounted) {
          final loc = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('offerLockedForAnotherDeal'))),
          );
        }
        return;
      }
      _lastEnsureChatError = null;
      await _asegurarChat();
      await _asegurarContraparte(miUid);
      if (_chatId == null || _chatId!.isEmpty) {
        if (mounted) {
          final extra = (_lastEnsureChatError ?? '').trim();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(extra.isEmpty
                  ? AppLocalizations.of(context).t('sendFailed')
                  : '${AppLocalizations.of(context).t('sendFailed')}: $extra'),
            ),
          );
        }
        return;
      }
      // Merge con Ãºltimo estado negociado (campo a campo)
      final ofertaSnap =
          await FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId).get();
      final ofertaData = ofertaSnap.data() ?? <String, dynamic>{};
      final last = await _getUltimaContraoferta();
      final merged = <String, dynamic>{};
      final rawPrecio = (contraoferta['precio'] ?? '').toString();
      final rawForma = (contraoferta['formaPago'] ?? '').toString();
      final rawFecha = (contraoferta['fecha'] ?? '').toString();
      final rawCantidad = (contraoferta['cantidad'] ?? '').toString().trim();
      final rawPenalizacion = _sanitizePenalizacionPayload(contraoferta['penalizacion']);
      merged['precio'] = _sanitizePrecio(rawPrecio).ifEmptyUse(
        (last?['precio'] ??
                ofertaData['precioFinal'] ??
                ofertaData['precio'] ??
                widget.precioInicial)
            .toString(),
      );
      merged['formaPago'] = _sanitizeFormaPago(rawForma).ifEmptyUse(
        (last?['formaPago'] ??
                ofertaData['formaPagoFinal'] ??
                ofertaData['formaPago'] ??
                widget.formaPago)
            .toString(),
      );
      merged['fecha'] = _sanitizeFecha(rawFecha).ifEmptyUse(
        (last?['fecha'] ??
                ofertaData['fechaSalidaFinal'] ??
                ofertaData['fecha'] ??
                widget.fechaSalida)
            .toString(),
      );
      merged['cantidad'] = rawCantidad.isNotEmpty
          ? rawCantidad
          : (last?['cantidad'] ??
                  ofertaData['cantidadFinal'] ??
                  ofertaData['cantidad'] ??
                  widget.cantidad)
              .toString();

      if (rawPenalizacion != null) {
        final penalizacionOk = await _registrarPenalizacionComprador(rawPenalizacion, miUid);
        if (!penalizacionOk) {
          return;
        }
      }

      final callable = FirebaseFunctions.instance.httpsCallable('sendContraofertaMessage');
      final resp = await callable.call<Map<String, dynamic>>({
        'ofertaId': widget.ofertaId,
        'coleccion': _coleccionActiva,
        'vendedorId': widget.vendedorId,
        if ((_counterpartUid ?? '').trim().isNotEmpty) 'counterpartUid': _counterpartUid!.trim(),
        'precio': merged['precio'],
        'formaPago': merged['formaPago'],
        'fecha': merged['fecha'],
        'cantidad': merged['cantidad'],
        if (rawPenalizacion != null) 'penalizacion': rawPenalizacion,
      });
      final data = resp.data;
      final resolvedChatId = (data['chatId'] ?? '').toString().trim();
      final resolvedCollection = (data['coleccion'] ?? '').toString().trim();
      if (resolvedCollection.isNotEmpty && _coleccionesOferta.contains(resolvedCollection)) {
        _coleccionActiva = resolvedCollection;
      }
      if (resolvedChatId.isEmpty) {
        throw StateError('chat_not_resolved');
      }
      if (mounted) {
        setState(() {
          _chatId = resolvedChatId;
        });
      } else {
        _chatId = resolvedChatId;
      }
      print('Contraoferta enviada en backend para chat: $resolvedChatId');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('proposalSent'))));
      }
    } catch (e) {
      print('Error al enviar contraoferta: $e');
      if (mounted) {
        final msg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).t('sendFailed')}: $msg')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendInProgress = false;
          _loadingSend = false;
        });
      } else {
        _sendInProgress = false;
        _loadingSend = false;
      }
    }
  }

  Future<bool> _puedeEscribirContraoferta(String miUid) async {
    try {
      final offerSnap =
          await FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId).get();
      if (!offerSnap.exists) return false;
      final data = offerSnap.data() ?? <String, dynamic>{};

      final enTrato = data['enTrato'] == true;
      if (!enTrato) return true;

      final vendedor =
          (data['vendedor'] ?? data['vendedorId'] ?? data['vendedorUid'] ?? '').toString();
      final comprador =
          (data['comprador'] ?? data['compradorId'] ?? data['compradorUid'] ?? '').toString();

      return miUid == vendedor || (comprador.isNotEmpty && miUid == comprador);
    } catch (_) {
      return false;
    }
  }

  Future<void> _asegurarContraparte(String miUid) async {
    final fixedCounterpartUid = (_counterpartUid ?? '').trim();
    if (fixedCounterpartUid.isNotEmpty && fixedCounterpartUid != miUid) {
      return;
    }

    final currentChatId = (_chatId ?? '').trim();
    if (currentChatId.isNotEmpty) {
      try {
        final chatSnap =
            await FirebaseFirestore.instance.collection('chats').doc(currentChatId).get();
        final data = chatSnap.data() ?? <String, dynamic>{};
        final vendedorId = (data['vendedorId'] ?? data['vendedor'] ?? '').toString().trim();
        final compradorId = (data['compradorId'] ?? data['comprador'] ?? '').toString().trim();
        if (vendedorId.isNotEmpty && vendedorId != miUid) {
          _counterpartUid = vendedorId;
          return;
        }
        if (compradorId.isNotEmpty && compradorId != miUid) {
          _counterpartUid = compradorId;
          return;
        }
        final participants =
            (data['participants'] as List?)?.map((e) => e.toString().trim()).toList() ?? <String>[];
        for (final participant in participants) {
          if (participant.isNotEmpty && participant != miUid) {
            _counterpartUid = participant;
            return;
          }
        }
      } catch (_) {}
    }

    final vendedorId = widget.vendedorId.trim();
    if (vendedorId.isNotEmpty && vendedorId != miUid) {
      _counterpartUid = vendedorId;
      return;
    }

    try {
      final offerSnap =
          await FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId).get();
      final data = offerSnap.data() ?? <String, dynamic>{};
      final compradorId = (data['comprador'] ?? data['compradorId'] ?? data['compradorUid'] ?? '')
          .toString()
          .trim();
      if (compradorId.isNotEmpty && compradorId != miUid) {
        _counterpartUid = compradorId;
      }
    } catch (_) {}
  }

  Future<void> _asegurarChat() async {
    if (_chatId != null) return; // ya inicializado
    final ofertaId = widget.ofertaId.trim();
    final fixedChatId = widget.chatId.trim();
    if (ofertaId.isEmpty && fixedChatId.isEmpty) {
      // Parar si los argumentos no son vÃ¡lidos
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    final miUid = user?.uid;
    if (miUid == null) {
      // Si no hay sesiÃ³n, detener aquÃ­; la lectura de mensajes puede fallar por permisos
      return;
    }

    final explicitCounterpartUid = (_counterpartUid ?? '').trim();
    String chatDocId = fixedChatId;
    if (chatDocId.isEmpty) {
      final vendedorId = widget.vendedorId.trim();
      if (explicitCounterpartUid.isNotEmpty && explicitCounterpartUid != miUid) {
        chatDocId = _composePairChatId(ofertaId, miUid, explicitCounterpartUid);
      } else if (vendedorId.isNotEmpty && vendedorId != miUid) {
        chatDocId = _composePairChatId(ofertaId, miUid, vendedorId);
      }
    }

    final canResolvePair = explicitCounterpartUid.isNotEmpty && explicitCounterpartUid != miUid;
    final canResolveBuyerToSeller =
        widget.vendedorId.trim().isNotEmpty && widget.vendedorId.trim() != miUid;
    final ensuredChatId = (canResolvePair || canResolveBuyerToSeller)
        ? await _ensurePairChatViaCallable(
            ofertaId: ofertaId,
            vendedorId: widget.vendedorId.trim(),
          )
        : '';
    if (ensuredChatId.isNotEmpty) {
      chatDocId = ensuredChatId;
    }

    if (chatDocId.isEmpty) {
      _lastEnsureChatError ??= 'chat_not_resolved';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).t('sendFailed'))),
        );
      }
      return;
    }

    // Establecer el chatId de inmediato para evitar spinner infinito
    if (mounted) {
      setState(() {
        _chatId = chatDocId;
      });
    } else {
      _chatId = chatDocId;
    }

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatDocId);
    DocumentSnapshot<Map<String, dynamic>> snap;
    try {
      snap = await chatRef.get();
    } on FirebaseException catch (e) {
      _lastEnsureChatError = e.code;
      return;
    }
    if (!snap.exists) {
      _lastEnsureChatError = 'chat_not_found';
      return;
    } else {
      // Validar que current user estÃ© en participants; si no, abortar por seguridad
      final data = snap.data();
      final coleccionChat = (data?['coleccion'] ?? '').toString();
      if (_coleccionesOferta.contains(coleccionChat) && coleccionChat != _coleccionActiva) {
        _coleccionActiva = coleccionChat;
      }
      if (coleccionChat.isEmpty) {
        await _resolverColeccionActiva();
        try {
          await chatRef.update({'coleccion': _coleccionActiva});
        } catch (_) {}
      }
      final participants = (data?['participants'] as List?)?.cast<String>() ?? [];
      final vendedorChatId = (data?['vendedorId'] ?? data?['vendedor'] ?? '').toString().trim();
      final compradorChatId = (data?['compradorId'] ?? data?['comprador'] ?? '').toString().trim();
      final isMember = participants.contains(miUid) ||
          (vendedorChatId.isNotEmpty && vendedorChatId == miUid) ||
          (compradorChatId.isNotEmpty && compradorChatId == miUid);
      if (!isMember) {
        if (mounted) {
          final loc = AppLocalizations.of(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loc.t('offerLockedForAnotherDeal'))),
          );
        }
        return;
      }

      try {
        await chatRef.update({
          'unreadFor': FieldValue.arrayRemove([miUid]),
        });
      } catch (_) {}
    }
  }

  bool _validRouteArgs() {
    // Permite abrir si hay ofertaId; si falta vendedorId, se intentarÃ¡ leer chat existente
    return widget.ofertaId.isNotEmpty;
  }

  double _parsePositiveDouble(dynamic raw) {
    final value = (raw ?? '').toString().trim().replaceAll(',', '.');
    if (value.isEmpty) return 0;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed <= 0) return 0;
    return parsed;
  }

  int _parsePositiveInt(dynamic raw, {int fallback = 1}) {
    final value = (raw ?? '').toString().trim();
    final parsed = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  String _resolveTipoPrecioActual(Map<String, dynamic> offerData) {
    final raw = (offerData['tipoPrecio'] ?? widget.tipoPrecio).toString().trim();
    return raw.isEmpty ? widget.tipoPrecio : raw;
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

  String _formatMoney(double amount) => amount.toStringAsFixed(2);

  Future<void> _aceptarPropuesta(Map<String, dynamic> msg) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final miUid = user?.uid;
      if (miUid == null) return;
      final ofertaRef =
          FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId);
      final loc = AppLocalizations.of(context);
      // Aceptar solo la Ãºltima contraoferta enviada por la contraparte.
      final ultimaContra = await _getUltimaContraofertaDeContraparte(miUid);
      if (ultimaContra == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Debes aceptar la ultima contraoferta enviada por la contraparte.'),
            ),
          );
        }
        return;
      }

      final fuenteFinal = <String, dynamic>{...msg, ...ultimaContra};
      final precioStr =
          _sanitizePrecio((fuenteFinal['precio'] ?? widget.precioInicial.toString()).toString())
              .ifEmptyUse(widget.precioInicial.toString());
      final formaPagoFinal =
          _sanitizeFormaPago((fuenteFinal['formaPago'] ?? widget.formaPago).toString())
              .ifEmptyUse(widget.formaPago);
      final fechaSalidaFinal =
          _sanitizeFecha((fuenteFinal['fecha'] ?? widget.fechaSalida).toString())
              .ifEmptyUse(widget.fechaSalida);
      final cantidadRaw = (fuenteFinal['cantidad'] ?? widget.cantidad).toString().trim();
      final ofertaSnapPreview = await ofertaRef.get();
      final dataBeforePreview = ofertaSnapPreview.data() ?? <String, dynamic>{};
      final cantidadFinal = _parsePositiveInt(
        cantidadRaw,
        fallback: _cantidadDisponibleBase(dataBeforePreview),
      );
      final tipoPrecioFinal = _resolveTipoPrecioActual(dataBeforePreview);
      final pesoOferta = _resolvePesoOfertaReferencia(dataBeforePreview);
      final usaPeso = _usaPesoParaComision(tipoPrecioFinal);
      final factorPesoComision = usaPeso ? (pesoOferta > 0 ? pesoOferta : 1) : 1;
      final precioDouble = double.tryParse(precioStr.replaceAll(',', '.')) ?? 0;
      final totalNegociado = precioDouble * cantidadFinal * factorPesoComision;
      // ComisiÃ³n 0.15% (0.0015) mÃ­nimo 1â‚¬
      final double comision = (totalNegociado * 0.0015).clamp(1.0, double.infinity).toDouble();
      final String comisionFmt = _formatMoney(comision);

      // Simular pasarela de pago
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setStateDlg) => AlertDialog(
            title: Text(loc.t('payCommission')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.tf('commissionAmount', {'amount': comisionFmt})),
                if (usaPeso)
                  Text(
                    'Base: ${precioDouble.toStringAsFixed(2)} x $cantidadFinal x ${factorPesoComision.toStringAsFixed(2)} ${_unidadPesoDesdeTipoPrecio(tipoPrecioFinal)}',
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(
                      width: 16, height: 16, child: Icon(Icons.lock, size: 16, color: Colors.grey)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(loc.t('commissionPayment')))
                ])
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false), child: Text(loc.t('cancel'))),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true), child: Text(loc.t('accept'))),
            ],
          ),
        ),
      );
      if (confirmed != true) return; // usuario cancelÃ³

      // Marcar enTrato (bloqueada) al primer pago y set expiraciÃ³n 24h si falta la otra parte
      final ofertaSnapBefore = await ofertaRef.get();
      final dataBefore = ofertaSnapBefore.data() ?? {};
      final yaPagadoComprador = dataBefore['pagadoComprador'] == true;
      final yaPagadoVendedor = dataBefore['pagadoVendedor'] == true;
      final yaAceptadoComprador = dataBefore['aceptadoComprador'] == true;
      final yaAceptadoVendedor = dataBefore['aceptadoVendedor'] == true;

      final vendedorOferta = (dataBefore['vendedor'] ??
              dataBefore['vendedorId'] ??
              dataBefore['vendedorUid'] ??
              widget.vendedorId)
          .toString();
      final miRol =
          (vendedorOferta.isNotEmpty && miUid == vendedorOferta) ? 'vendedor' : 'comprador';
      final otroRol = miRol == 'vendedor' ? 'comprador' : 'vendedor';
      final penalizacionEstado = (dataBefore['penalizacionEstado'] ?? '').toString().trim();
      if (miRol == 'vendedor' && penalizacionEstado == 'pendiente') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Resuelve antes la penalizacion propuesta por el comprador.'),
            ),
          );
        }
        return;
      }

      final updates = <String, dynamic>{
        'enTrato': true, // bloquear
        'pagado${_cap(miRol)}': true,
        'aceptado${_cap(miRol)}': true,
        'precioFinal': precioStr,
        'formaPagoFinal': formaPagoFinal,
        'fechaSalidaFinal': fechaSalidaFinal,
        'cantidadFinal': cantidadFinal.toString(),
        'tipoPrecioFinal': tipoPrecioFinal,
        if (pesoOferta > 0) 'pesoMedioReferenciaComision': pesoOferta.toString(),
        if (_unidadPesoDesdeTipoPrecio(tipoPrecioFinal).isNotEmpty)
          'unidadPesoReferenciaComision': _unidadPesoDesdeTipoPrecio(tipoPrecioFinal),
        'totalNegociadoBaseComision': _formatMoney(totalNegociado),
        'comisionCalculada': comisionFmt,
        'comisionRate': 0.0015,
        'contraofertaAceptadaDeUid': (ultimaContra['remitenteUid'] ?? '').toString(),
        if (ultimaContra['timestamp'] != null) 'contraofertaAceptadaAt': ultimaContra['timestamp'],
      };
      if (penalizacionEstado == 'aceptada' && dataBefore['penalizacionFinal'] is Map) {
        updates['penalizacionFinal'] = dataBefore['penalizacionFinal'];
      }
      if (miRol == 'comprador') {
        updates['comprador'] = miUid;
      }

      final ahora = DateTime.now();
      // Si el otro aÃºn no ha pagado, crear ventana de expiraciÃ³n 24h
      final otroPago = otroRol == 'comprador' ? yaPagadoComprador : yaPagadoVendedor;
      final otroAcepto = otroRol == 'comprador' ? yaAceptadoComprador : yaAceptadoVendedor;
      final tratoCerradoPrevio = dataBefore['vendido'] == true ||
          (yaAceptadoComprador && yaAceptadoVendedor) ||
          _parseIsoOrNull(dataBefore['fechaCierreTrato']) != null;
      final cerrarTrato = otroPago || otroAcepto || tratoCerradoPrevio;

      if (!cerrarTrato) {
        updates['ventanaTratoInicio'] = ahora.toIso8601String();
        updates['ventanaTratoExpira'] = ahora.add(const Duration(hours: 24)).toIso8601String();
        updates['fechaCierreTrato'] = null; // para poder filtrar en funciÃ³n programada
        updates['expirado'] = false;
      } else {
        // Ambos han pagado: cerrar trato definitivamente
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

      // NotificaciÃ³n a la otra parte (resuelve token en backend)
      String otroUid =
          (miRol == 'vendedor') ? (dataBefore['comprador'] ?? '').toString() : widget.vendedorId;
      if (otroUid.isEmpty && _chatId != null && _chatId!.isNotEmpty) {
        try {
          final chatSnap = await FirebaseFirestore.instance.collection('chats').doc(_chatId).get();
          if (chatSnap.exists) {
            final chatData = chatSnap.data() ?? <String, dynamic>{};
            final participants =
                (chatData['participants'] as List?)?.map((e) => e.toString()).toList() ?? [];
            otroUid = participants.firstWhere((p) => p.isNotEmpty && p != miUid, orElse: () => '');
          }
        } catch (_) {}
      }
      if (otroUid.isNotEmpty) {
        final callable = FirebaseFunctions.instance.httpsCallable('sendOfferPush');
        await callable.call<Map<String, dynamic>>({
          'targetUid': otroUid,
          'ofertaId': widget.ofertaId,
          'tipo': cerrarTrato ? 'trato_cerrado' : 'oferta_aceptada',
          'title': cerrarTrato ? loc.t('dealClosed') : loc.t('dealPending'),
          'body': cerrarTrato ? loc.t('dealClosedMsg') : loc.t('dealPendingMsg'),
        });
      }

      if (cerrarTrato) {
        // Mostrar franja azul / confirmaciÃ³n ambos pagaron
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('dealClosed'))));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(loc.t('dealPending'))));
        }
      }
    } catch (e) {
      print('Error al aceptar propuesta: $e');
    }
  }

  Future<void> _mostrarResumenTrato(Map<String, dynamic>? ofertaData) async {
    final loc = AppLocalizations.of(context);
    final appState = MyApp.of(context);
    final bilingual = appState?.bilingualMode ?? false;

    final data = <String, dynamic>{...?ofertaData};
    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final vendedorOferta =
        (data['vendedor'] ?? data['vendedorId'] ?? data['vendedorUid'] ?? widget.vendedorId)
            .toString();
    final compradorOferta =
        (data['comprador'] ?? data['compradorId'] ?? data['compradorUid'] ?? '').toString();
    final tratoCerrado = data['vendido'] == true ||
        (data['aceptadoComprador'] == true && data['aceptadoVendedor'] == true) ||
        _parseIsoOrNull(data['fechaCierreTrato']) != null;
    final esParteTrato = miUid.isNotEmpty &&
        (miUid == vendedorOferta || (compradorOferta.isNotEmpty && miUid == compradorOferta));
    if (!esParteTrato) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.t('offerLockedForAnotherDeal'))),
        );
      }
      return;
    }

    final ultimaContra = await _getUltimaContraoferta();

    final raza = (data['raza'] ?? widget.raza).toString();
    final cantidad = (data['cantidadFinal'] ?? data['cantidad'] ?? widget.cantidad).toString();
    final descripcion =
        (data['descripcionAnimales'] ?? data['descripcion'] ?? data['detalles'] ?? '').toString();
    final tipoPrecio = (data['tipoPrecio'] ?? widget.tipoPrecio).toString();

    final precioFinal = (data['precioFinal'] ??
            ultimaContra?['precio'] ??
            data['precio'] ??
            widget.precioInicial.toString())
        .toString();
    final formaPagoFinal = (data['formaPagoFinal'] ??
            ultimaContra?['formaPago'] ??
            data['formaPago'] ??
            widget.formaPago)
        .toString();
    final fechaSalidaFinal =
        (data['fechaSalidaFinal'] ?? ultimaContra?['fecha'] ?? data['fecha'] ?? widget.fechaSalida)
            .toString();
    final penalizacionLineas =
        _penalizacionResumenLineas(data['penalizacionFinal'] ?? data['penalizacionPropuesta']);
    final unspecified =
        bilingual ? AppLocalizations.bilingual('unspecified') : loc.t('unspecified');
    final formaPagoDisplay = formaPagoFinal.trim().isEmpty ? unspecified : formaPagoFinal;
    final fechaSalidaDisplay = fechaSalidaFinal.trim().isEmpty ? unspecified : fechaSalidaFinal;

    Future<Map<String, String>> loadUserContact(String uid) async {
      if (uid.trim().isEmpty) {
        return <String, String>{'nombre': 'Sin nombre', 'telefono': 'No disponible'};
      }
      final snap = await FirebaseFirestore.instance.collection('usuarios').doc(uid.trim()).get();
      final userData = snap.data() ?? <String, dynamic>{};
      final nombre = (userData['nombre'] ?? '').toString().trim();
      final apellidos = (userData['apellidos'] ?? '').toString().trim();
      final nombreCompleto = [nombre, apellidos].where((part) => part.isNotEmpty).join(' ').trim();
      final telefono = (userData['telefono'] ?? '').toString().trim();
      return <String, String>{
        'nombre': nombreCompleto.isEmpty ? 'Sin nombre' : nombreCompleto,
        'telefono': telefono.isEmpty ? 'No disponible' : telefono,
      };
    }

    String normalizeDialPhone(String raw) {
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

    Future<void> copyPhone(String phone) async {
      final clean = phone.trim();
      if (clean.isEmpty || clean == 'No disponible') return;
      await Clipboard.setData(ClipboardData(text: clean));
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(content: Text('Telefono copiado')),
      );
    }

    Future<void> callPhone(String phone) async {
      final dial = normalizeDialPhone(phone);
      if (dial.isEmpty) return;
      final uri = Uri(scheme: 'tel', path: dial);
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el telefono')),
        );
      }
    }

    Map<String, String>? vendedorContacto;
    Map<String, String>? compradorContacto;
    if (tratoCerrado) {
      final contacts = await Future.wait<Map<String, String>>([
        loadUserContact(vendedorOferta),
        loadUserContact(compradorOferta),
      ]);
      vendedorContacto = contacts[0];
      compradorContacto = contacts[1];
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(bilingual ? AppLocalizations.bilingual('reviewDeal') : loc.t('reviewDeal')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${bilingual ? AppLocalizations.bilingual('race') : loc.t('race')}: $raza'),
              const SizedBox(height: 4),
              Text(
                  '${bilingual ? AppLocalizations.bilingual('quantity') : loc.t('quantity')}: $cantidad'),
              if (descripcion.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                    '${bilingual ? AppLocalizations.bilingual('description') : loc.t('description')}: $descripcion'),
              ],
              const SizedBox(height: 12),
              Text(
                '${bilingual ? AppLocalizations.bilingual('price') : loc.t('price')}: $precioFinal ${_tipoPrecioDisplay(tipoPrecio)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${bilingual ? AppLocalizations.bilingual('paymentMethod') : loc.t('paymentMethod')}: $formaPagoDisplay',
              ),
              const SizedBox(height: 4),
              Text(
                '${bilingual ? AppLocalizations.bilingual('estimatedExitDate') : loc.t('estimatedExitDate')}: $fechaSalidaDisplay',
              ),
              if (penalizacionLineas.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  'Penalizacion:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final line in penalizacionLineas) ...[
                  const SizedBox(height: 2),
                  Text('â€¢ $line'),
                ],
              ],
              if (tratoCerrado) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 6),
                const Text(
                  'Contactos para coordinar la carga',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text('Vendedor: ${vendedorContacto?['nombre'] ?? 'Sin nombre'}'),
                Text('Telefono: ${vendedorContacto?['telefono'] ?? 'No disponible'}'),
                if ((vendedorContacto?['telefono'] ?? 'No disponible') != 'No disponible')
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => callPhone(vendedorContacto?['telefono'] ?? ''),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Llamar'),
                      ),
                      TextButton.icon(
                        onPressed: () => copyPhone(vendedorContacto?['telefono'] ?? ''),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text('Comprador: ${compradorContacto?['nombre'] ?? 'Sin nombre'}'),
                Text('Telefono: ${compradorContacto?['telefono'] ?? 'No disponible'}'),
                if ((compradorContacto?['telefono'] ?? 'No disponible') != 'No disponible')
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => callPhone(compradorContacto?['telefono'] ?? ''),
                        icon: const Icon(Icons.call, size: 18),
                        label: const Text('Llamar'),
                      ),
                      TextButton.icon(
                        onPressed: () => copyPhone(compradorContacto?['telefono'] ?? ''),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                      ),
                    ],
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(bilingual ? AppLocalizations.bilingual('close') : loc.t('close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final appState = MyApp.of(context);
    final bilingual = appState?.bilingualMode ?? false;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF004d26),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              const Text(
                'CONTRAOFERTA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // Banner de estado del trato y expiraciÃ³n 24h
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection(_coleccionActiva)
                    .doc(widget.ofertaId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
                  final data = snapshot.data!.data() ?? {};
                  final now = DateTime.now();
                  final fechaCierre = _parseIsoOrNull(data['fechaCierreTrato']);
                  final ventanaExpira = _parseIsoOrNull(data['ventanaTratoExpira']);
                  Widget? banner;
                  final expirado = data['expirado'] == true;
                  final tratoCerrado = data['vendido'] == true ||
                      (data['aceptadoComprador'] == true && data['aceptadoVendedor'] == true) ||
                      fechaCierre != null;
                  if (tratoCerrado) {
                    banner = _buildBanner(
                      color: Colors.green.shade700,
                      text: bilingual
                          ? AppLocalizations.bilingual('dealClosed')
                          : loc.t('dealClosed'),
                      textColor: Colors.white,
                    );
                  } else if (expirado) {
                    banner = _buildBanner(
                      color: Colors.red.shade300,
                      text: bilingual
                          ? AppLocalizations.bilingual('dealExpired')
                          : loc.t('dealExpired'),
                      textColor: Colors.white,
                    );
                  } else if (ventanaExpira != null) {
                    if (now.isBefore(ventanaExpira)) {
                      final remaining = ventanaExpira
                          .difference(now)
                          .inMinutes; // mÃ¡s granular mientras estÃ¡ pendiente
                      final hours = (remaining / 60).floor();
                      final mins = remaining % 60;
                      final remainingStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
                      banner = _buildBanner(
                        color: Colors.orange.shade200,
                        text: loc.tf('dealExpiresIn', {'hours': remainingStr}),
                        textColor: Colors.black87,
                      );
                    } else {
                      banner = _buildBanner(
                        color: Colors.red.shade200,
                        text: bilingual
                            ? AppLocalizations.bilingual('dealExpired')
                            : loc.t('dealExpired'),
                        textColor: Colors.red.shade800,
                      );
                    }
                  }
                  return banner ?? const SizedBox.shrink();
                },
              ),
              Expanded(
                child: _chatId == null
                    ? _buildMensajesFallback(loc, bilingual)
                    : StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('mensajes')
                            .where('chatId', isEqualTo: _chatId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            if (_mensajesCache.isNotEmpty) {
                              return _buildMensajesListFromMaps(_mensajesCache);
                            }
                            return _buildMensajesFallback(loc, bilingual);
                          }

                          if (snapshot.connectionState == ConnectionState.waiting) {
                            if (_mensajesCache.isNotEmpty) {
                              return _buildMensajesListFromMaps(_mensajesCache);
                            }
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            if (_mensajesCache.isNotEmpty) {
                              return _buildMensajesListFromMaps(_mensajesCache);
                            }
                            return _buildMensajesFallback(loc, bilingual);
                          }

                          final mensajesStream = [...snapshot.data!.docs]..sort((a, b) {
                              final aMap = a.data() as Map<String, dynamic>;
                              final bMap = b.data() as Map<String, dynamic>;
                              return _compareByTimestampAsc(aMap, bMap);
                            });

                          _mensajesCache =
                              mensajesStream.map((d) => d.data() as Map<String, dynamic>).toList();

                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                _scrollController.position.maxScrollExtent,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                              );
                            }
                          });

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16.0),
                            itemCount: mensajesStream.length,
                            itemBuilder: (context, index) {
                              final msg = mensajesStream[index].data() as Map<String, dynamic>;
                              final user = FirebaseAuth.instance.currentUser;
                              final miUid = user?.uid;
                              final esMio = msg['remitenteUid'] == miUid;

                              // Diferentes tipos de mensaje
                              if ((msg['tipo'] ?? 'contraoferta') == 'mensaje_texto') {
                                return _buildMensajeTexto(msg, esMio);
                              } else {
                                return _buildMensajeContraoferta(msg, esMio);
                              }
                            },
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection(_coleccionActiva)
                      .doc(widget.ofertaId)
                      .snapshots(),
                  builder: (context, ofertaSnap) {
                    final ofertaData = ofertaSnap.data?.data() ?? <String, dynamic>{};
                    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    final vendedorOferta = (ofertaData['vendedor'] ??
                            ofertaData['vendedorId'] ??
                            ofertaData['vendedorUid'] ??
                            widget.vendedorId)
                        .toString();
                    final compradorOferta = (ofertaData['comprador'] ??
                            ofertaData['compradorId'] ??
                            ofertaData['compradorUid'] ??
                            '')
                        .toString();
                    final soyVendedor =
                        miUid.isNotEmpty && vendedorOferta.isNotEmpty && miUid == vendedorOferta;
                    final esCompradorDelTrato =
                        compradorOferta.isNotEmpty && miUid.isNotEmpty && miUid == compradorOferta;
                    final esParteTrato = soyVendedor || esCompradorDelTrato;
                    final now = DateTime.now();
                    DateTime? ventanaExpira;
                    try {
                      final rawExp = ofertaData['ventanaTratoExpira'];
                      if (rawExp is String && rawExp.isNotEmpty) {
                        ventanaExpira = DateTime.parse(rawExp);
                      }
                    } catch (_) {}
                    final expirado = ofertaData['expirado'] == true;
                    final expiradaPorTiempo = ventanaExpira != null && !now.isBefore(ventanaExpira);
                    final tratoExpirado = expirado || expiradaPorTiempo;
                    final tratoCerrado = ofertaData['vendido'] == true ||
                        (ofertaData['aceptadoComprador'] == true &&
                            ofertaData['aceptadoVendedor'] == true) ||
                        _parseIsoOrNull(ofertaData['fechaCierreTrato']) != null;
                    final yaAcepteBase = soyVendedor
                        ? ofertaData['aceptadoVendedor'] == true
                        : (esCompradorDelTrato && ofertaData['aceptadoComprador'] == true);
                    final yaAcepte = tratoCerrado || (yaAcepteBase && !tratoExpirado);
                    final bloqueoParaOtroComprador = ofertaData['enTrato'] == true && !esParteTrato;
                    final estadoPenalizacion =
                        (ofertaData['penalizacionEstado'] ?? '').toString().trim();
                    final penalizacionPropuesta =
                        _sanitizePenalizacionPayload(ofertaData['penalizacionPropuesta']);
                    final mostrarDecisionPenalizacionVendedor = soyVendedor &&
                        estadoPenalizacion == 'pendiente' &&
                        penalizacionPropuesta != null;
                    final mostrarEstadoPenalizacionComprador =
                        !soyVendedor && estadoPenalizacion.isNotEmpty;
                    final penalizacionLineas = _penalizacionResumenLineas(penalizacionPropuesta);

                    Widget actionWidget;
                    if (bloqueoParaOtroComprador) {
                      actionWidget = SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade600,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(loc.t('offerLockedForAnotherDeal')),
                        ),
                      );
                    } else if (yaAcepte) {
                      actionWidget = SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => _mostrarResumenTrato(ofertaData),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004d26),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(bilingual
                              ? AppLocalizations.bilingual('reviewDeal')
                              : loc.t('reviewDeal')),
                        ),
                      );
                    } else {
                      actionWidget = Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSending
                                  ? null
                                  : () async {
                                      final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                                      final ultima = miUid.isEmpty
                                          ? null
                                          : await _getUltimaContraofertaDeContraparte(miUid);
                                      if (ultima == null) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              bilingual
                                                  ? AppLocalizations.bilingual('noMessages')
                                                  : loc.t('noMessages'),
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      await _aceptarPropuesta(ultima);
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF004d26),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Aceptar oferta'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isSending ? null : _abrirDialogoContraoferta,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    _isSending ? Colors.grey.shade600 : const Color(0xFF004d26),
                                foregroundColor: Colors.white,
                              ),
                              child: Text(_isSending ? 'Enviando...' : 'Contraoferta'),
                            ),
                          ),
                        ],
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          actionWidget,
                          if (mostrarDecisionPenalizacionVendedor) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                border: Border.all(color: Colors.orange.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Penalizacion propuesta por el comprador',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  for (final line in penalizacionLineas) ...[
                                    const SizedBox(height: 4),
                                    Text('â€¢ $line'),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _isSending
                                              ? null
                                              : () =>
                                                  _resolverSolicitudPenalizacion(aceptar: false),
                                          child: const Text('Rechazar penalizacion'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _isSending
                                              ? null
                                              : () => _resolverSolicitudPenalizacion(aceptar: true),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF004d26),
                                            foregroundColor: Colors.white,
                                          ),
                                          child: const Text('Aceptar penalizacion'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (mostrarEstadoPenalizacionComprador) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.shade50,
                                border: Border.all(color: Colors.blueGrey.shade200),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _buildPenalizacionEstadoTexto(ofertaData),
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  if (estadoPenalizacion == 'rechazada') ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: _isSending ? null : _continuarSinPenalizacion,
                                        child: const Text('Continuar sin penalizacion'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          if (_isSending) ModalBarrier(dismissible: false, color: Colors.black.withOpacity(0.08)),
          if (_isSending)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildMensajeTexto(Map<String, dynamic> msg, bool esMio) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: esMio ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: esMio ? const Color(0xFF004d26) : Colors.grey[300],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              (msg['texto'] ?? '').toString(),
              style: TextStyle(
                color: esMio ? Colors.white : Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMensajesListFromMaps(List<Map<String, dynamic>> lista) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16.0),
      itemCount: lista.length,
      itemBuilder: (context, index) {
        final msg = lista[index];
        final user = FirebaseAuth.instance.currentUser;
        final miUid = user?.uid;
        final esMio = msg['remitenteUid'] == miUid;
        if ((msg['tipo'] ?? 'contraoferta') == 'mensaje_texto') {
          return _buildMensajeTexto(msg, esMio);
        }
        return _buildMensajeContraoferta(msg, esMio);
      },
    );
  }

  Widget _buildMensajesFallback(AppLocalizations loc, bool bilingual) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _obtenerMensajesCompat(),
      builder: (context, fallbackSnapshot) {
        if (fallbackSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final lista = fallbackSnapshot.data ?? <Map<String, dynamic>>[];
        if (lista.isEmpty) {
          return Center(
            child: Text(
              bilingual ? AppLocalizations.bilingual('noMessages') : loc.t('noMessages'),
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        _mensajesCache = lista;
        final firstChatId = lista
            .map((msg) => (msg['chatId'] ?? '').toString().trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        if (firstChatId.isNotEmpty && firstChatId != _chatId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _chatId = firstChatId;
            });
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        return _buildMensajesListFromMaps(lista);
      },
    );
  }

  Widget _buildMensajeContraoferta(Map<String, dynamic> msg, bool esMio) {
    final loc = AppLocalizations.of(context);
    final appState = MyApp.of(context);
    final bilingual = appState?.bilingualMode ?? false;
    final timestamp =
        msg['timestamp'] != null ? (msg['timestamp'] as Timestamp).toDate() : DateTime.now();
    final penalizacionLineas = _penalizacionResumenLineas(msg['penalizacion']);

    return Row(
      mainAxisAlignment: esMio ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
          decoration: BoxDecoration(
            color: esMio ? const Color(0xFFE8F5E8) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${bilingual ? AppLocalizations.bilingual('price') : loc.t('price')}: ${msg['precio'] ?? loc.t('unspecified')} ${_tipoPrecioDisplay(widget.tipoPrecio)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${bilingual ? AppLocalizations.bilingual('paymentMethod') : loc.t('paymentMethod')}: ${msg['formaPago'] ?? loc.t('unspecified')}',
              ),
              const SizedBox(height: 2),
              Text(
                '${bilingual ? AppLocalizations.bilingual('estimatedExitDate') : loc.t('estimatedExitDate')}: ${msg['fecha'] ?? loc.t('unspecified')}',
              ),
              if ((msg['cantidad'] ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  '${bilingual ? AppLocalizations.bilingual('quantity') : loc.t('quantity')}: ${msg['cantidad']}',
                ),
              ],
              if (penalizacionLineas.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'Penalizacion:',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                for (final line in penalizacionLineas) ...[
                  const SizedBox(height: 2),
                  Text('â€¢ $line'),
                ],
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<Map<String, dynamic>?> _getUltimaContraoferta() async {
    final lista = await _obtenerMensajesCompat();
    for (final msg in lista) {
      final tipo = (msg['tipo'] ?? 'contraoferta').toString();
      if (tipo == 'contraoferta') {
        return msg;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getUltimaContraofertaDeContraparte(String miUid) async {
    final lista = await _obtenerMensajesCompat();
    for (final msg in lista) {
      final tipo = (msg['tipo'] ?? 'contraoferta').toString();
      final remitente = (msg['remitenteUid'] ?? '').toString();
      if (tipo == 'contraoferta' && remitente.isNotEmpty && remitente != miUid) {
        return msg;
      }
    }
    return null;
  }

  Future<void> _abrirDialogoContraoferta() async {
    final loc = AppLocalizations.of(context);
    final appState = MyApp.of(context);
    final bilingual = appState?.bilingualMode ?? false;
    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    final ofertaSnap =
        await FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId).get();
    final ofertaData = ofertaSnap.data() ?? <String, dynamic>{};
    final ultimaContra = await _getUltimaContraoferta();

    // Cargar precio vigente (Ãºltima contraoferta o datos base de la oferta)
    final precioActual = _sanitizePrecio(
      (ultimaContra?['precio'] ?? ofertaData['precioFinal'] ?? ofertaData['precio'] ?? '')
          .toString(),
    ).ifEmptyUse(_sanitizePrecio(widget.precioInicial.toString()).ifEmptyUse(_precioFormCtrl.text));
    _precioFormCtrl.text = precioActual;

    // Cargar forma de pago vigente (editable para negociaciÃ³n conjunta)
    final formaPagoActual = _sanitizeFormaPago(
      (ultimaContra?['formaPago'] ?? ofertaData['formaPagoFinal'] ?? ofertaData['formaPago'] ?? '')
          .toString(),
    ).ifEmptyUse(_formaPagoForm);
    if (_formasPagoPermitidas.contains(formaPagoActual)) {
      _formaPagoForm = formaPagoActual;
    }

    // Cargar fecha de salida vigente (editable para negociaciÃ³n conjunta)
    final fechaSalidaActual =
        (ultimaContra?['fecha'] ?? ofertaData['fechaSalidaFinal'] ?? ofertaData['fecha'] ?? '')
            .toString()
            .trim();
    final fechaCargada = _parseDate(fechaSalidaActual);
    _fechaForm = fechaCargada;

    final vendedorOferta =
        (ofertaData['vendedor'] ?? ofertaData['vendedorId'] ?? ofertaData['vendedorUid'] ?? '')
            .toString()
            .trim();
    final soyVendedor = miUid.isNotEmpty && vendedorOferta.isNotEmpty && miUid == vendedorOferta;
    final maxCantidad = _cantidadMaximaPermitida(ofertaData);
    final puedeEditarPenalizacion = !soyVendedor;
    final penalizacionBase = _normalizePenalizacion(
      ofertaData['penalizacionEstado'] == 'aceptada'
          ? ofertaData['penalizacionFinal']
          : ofertaData['penalizacionPropuesta'],
    );

    // Cargar cantidad vigente del Ãºltimo mensaje
    final cantidadVigente =
        (ultimaContra?['cantidad'] ?? ofertaData['cantidadFinal'] ?? ofertaData['cantidad'] ?? '')
            .toString()
            .trim();
    _cantidadFormCtrl.text = cantidadVigente;

    final penalizacionHabilitadaInicial = _penalizacionTieneReglas(penalizacionBase);
    final Map<String, bool> reglaActiva = <String, bool>{};
    final Map<String, String> reglaTipo = <String, String>{};
    final Map<String, TextEditingController> umbralCtrls = <String, TextEditingController>{};
    final Map<String, TextEditingController> valorCtrls = <String, TextEditingController>{};
    final Map<String, TextEditingController> descripcionCtrls = <String, TextEditingController>{};
    for (final key in _penalizacionRuleKeys) {
      final item = Map<String, dynamic>.from(penalizacionBase[key] as Map<String, dynamic>);
      reglaActiva[key] = item['activa'] == true;
      reglaTipo[key] = (item['tipo'] ?? 'descuento').toString();
      umbralCtrls[key] = TextEditingController(text: (item['umbral'] ?? '').toString());
      valorCtrls[key] = TextEditingController(text: (item['valor'] ?? '').toString());
      if (key == 'defectoAnimal') {
        descripcionCtrls[key] = TextEditingController(text: (item['descripcion'] ?? '').toString());
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var penalizacionHabilitada = penalizacionHabilitadaInicial;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildPesoPenaltyGroup({
              required String title,
              required List<String> keys,
            }) {
              final selectedKey = _getSelectedPenaltyGroupKey(reglaActiva, keys);
              final selectedItem = selectedKey == null
                  ? null
                  : Map<String, dynamic>.from(
                      penalizacionBase[selectedKey] as Map<String, dynamic>);
              final selectedTipo =
                  selectedKey == null ? 'descuento' : (reglaTipo[selectedKey] ?? 'descuento');
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Individual'),
                      value: keys[0],
                      groupValue: selectedKey,
                      toggleable: puedeEditarPenalizacion,
                      onChanged: puedeEditarPenalizacion
                          ? (value) => setDialogState(
                                () => _setSelectedPenaltyGroupKey(reglaActiva, keys, value),
                              )
                          : null,
                    ),
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Colectivo'),
                      value: keys[1],
                      groupValue: selectedKey,
                      toggleable: puedeEditarPenalizacion,
                      onChanged: puedeEditarPenalizacion
                          ? (value) => setDialogState(
                                () => _setSelectedPenaltyGroupKey(reglaActiva, keys, value),
                              )
                          : null,
                    ),
                    if (selectedKey != null) ...[
                      TextFormField(
                        controller: umbralCtrls[selectedKey],
                        enabled: puedeEditarPenalizacion,
                        maxLength: 20,
                        decoration: InputDecoration(
                          labelText: selectedItem == null
                              ? 'Umbral'
                              : 'Umbral (${_penalizacionRuleLabels[selectedKey] ?? selectedKey})',
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedTipo,
                        items: _penalizacionTypeLabels.entries
                            .map(
                              (entry) => DropdownMenuItem<String>(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                            )
                            .toList(),
                        onChanged: puedeEditarPenalizacion
                            ? (value) {
                                if (value == null) return;
                                setDialogState(() => reglaTipo[selectedKey] = value);
                              }
                            : null,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                      ),
                      if (selectedTipo == 'descuento') ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: valorCtrls[selectedKey],
                          enabled: puedeEditarPenalizacion,
                          maxLength: 30,
                          decoration: const InputDecoration(
                            labelText: 'Valor (ej. 5â‚¬/kg o 30â‚¬)',
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              );
            }

            return AlertDialog(
              title: const Text('Contraoferta'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _precioFormCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      maxLength: 4,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]'))],
                      decoration: InputDecoration(
                        labelText:
                            '${bilingual ? AppLocalizations.bilingual('price') : loc.t('price')} (${_tipoPrecioDisplay(widget.tipoPrecio)})',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _cantidadFormCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText:
                            '${bilingual ? AppLocalizations.bilingual('quantity') : loc.t('quantity')} (max $maxCantidad)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _formaPagoForm,
                      items: _formasPagoPermitidas
                          .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                          .toList(),
                      onChanged: (v) {
                        final nextValue = v ?? _formaPagoForm;
                        setState(() => _formaPagoForm = nextValue);
                        setDialogState(() => _formaPagoForm = nextValue);
                      },
                      decoration: InputDecoration(
                        labelText: bilingual
                            ? AppLocalizations.bilingual('paymentMethod')
                            : loc.t('paymentMethod'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _fechaForm == null
                                ? (bilingual
                                    ? AppLocalizations.bilingual('estimatedExitDate')
                                    : loc.t('estimatedExitDate'))
                                : _formatDate(_fechaForm!),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final now = DateTime.now();
                            final initial = _fechaForm ?? now.add(const Duration(days: 1));
                            final picked = await showDatePicker(
                              context: context,
                              firstDate: now,
                              lastDate: DateTime(now.year + 2),
                              initialDate: initial.isBefore(now) ? now : initial,
                            );
                            if (picked != null) {
                              setState(() => _fechaForm = picked);
                              setDialogState(() => _fechaForm = picked);
                            }
                          },
                          child: Text(
                              bilingual ? AppLocalizations.bilingual('change') : loc.t('change')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: penalizacionHabilitada,
                      onChanged: (value) => setDialogState(() => penalizacionHabilitada = value),
                      title: const Text('Penalizacion por peso o defecto'),
                      subtitle: Text(
                        puedeEditarPenalizacion
                            ? 'Activalo si quieres proponer minimos, maximos o defectos.'
                            : 'La penalizacion la propone el comprador y tu la aceptas o rechazas abajo.',
                      ),
                    ),
                    if (penalizacionHabilitada) ...[
                      const SizedBox(height: 8),
                      buildPesoPenaltyGroup(
                        title: 'Penalizacion por peso minimo',
                        keys: _penalizacionMinimoKeys,
                      ),
                      buildPesoPenaltyGroup(
                        title: 'Penalizacion por peso maximo',
                        keys: _penalizacionMaximoKeys,
                      ),
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Penalizacion por defecto o diferencia'),
                              value: reglaActiva['defectoAnimal'] == true,
                              onChanged: puedeEditarPenalizacion
                                  ? (value) => setDialogState(
                                        () => reglaActiva['defectoAnimal'] = value == true,
                                      )
                                  : null,
                            ),
                            if (reglaActiva['defectoAnimal'] == true) ...[
                              TextFormField(
                                controller: descripcionCtrls['defectoAnimal'],
                                enabled: puedeEditarPenalizacion,
                                maxLength: 120,
                                decoration: const InputDecoration(
                                  labelText: 'Descripcion del defecto',
                                ),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: reglaTipo['defectoAnimal'],
                                items: _penalizacionTypeLabels.entries
                                    .map(
                                      (entry) => DropdownMenuItem<String>(
                                        value: entry.key,
                                        child: Text(entry.value),
                                      ),
                                    )
                                    .toList(),
                                onChanged: puedeEditarPenalizacion
                                    ? (value) {
                                        if (value == null) return;
                                        setDialogState(
                                          () => reglaTipo['defectoAnimal'] = value,
                                        );
                                      }
                                    : null,
                                decoration: const InputDecoration(labelText: 'Tipo'),
                              ),
                              if ((reglaTipo['defectoAnimal'] ?? 'descuento') == 'descuento') ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: valorCtrls['defectoAnimal'],
                                  enabled: puedeEditarPenalizacion,
                                  maxLength: 30,
                                  decoration: const InputDecoration(
                                    labelText: 'Valor (ej. 5â‚¬/kg o 30â‚¬)',
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isSending ? null : () => Navigator.of(dialogContext).pop(),
                  child: Text(bilingual ? AppLocalizations.bilingual('cancel') : loc.t('cancel')),
                ),
                ElevatedButton(
                  onPressed: _isSending
                      ? null
                      : () async {
                          final raw = _precioFormCtrl.text.trim();
                          final ok = _isPrecioInputValido(raw);
                          if (!ok) {
                            const msg =
                                'MÃ¡ximo 4 caracteres. Si usas decimal, puedes usar punto o coma.';
                            if (!mounted) return;
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(content: Text(msg)));
                            return;
                          }

                          Map<String, dynamic>? penalizacionPayload;
                          if (penalizacionHabilitada && puedeEditarPenalizacion) {
                            final rawPenalizacion = <String, dynamic>{};
                            for (final key in _penalizacionRuleKeys) {
                              rawPenalizacion[key] = <String, dynamic>{
                                'activa': reglaActiva[key] == true,
                                'umbral': umbralCtrls[key]?.text.trim() ?? '',
                                'tipo': reglaTipo[key] ?? 'descuento',
                                'valor': valorCtrls[key]?.text.trim() ?? '',
                                if (key == 'defectoAnimal')
                                  'descripcion': descripcionCtrls[key]?.text.trim() ?? '',
                              };
                            }
                            penalizacionPayload = _sanitizePenalizacionPayload(rawPenalizacion);
                          }

                          final payload = {
                            'precio': raw,
                            'formaPago': _formaPagoForm,
                            'fecha': _fechaForm != null ? _formatDate(_fechaForm!) : '',
                            'cantidad': _cantidadFormCtrl.text.trim(),
                            if (penalizacionPayload != null) 'penalizacion': penalizacionPayload,
                          };

                          // Cerrar de inmediato para evitar toques repetidos en "Enviar".
                          Navigator.of(dialogContext).pop();
                          unawaited(enviarContraoferta(payload));
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSending ? Colors.grey.shade600 : const Color(0xFF004d26),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _isSending
                        ? 'Enviando...'
                        : (bilingual ? AppLocalizations.bilingual('send') : loc.t('send')),
                  ),
                ),
              ],
            );
          },
        );
      },
    ).whenComplete(() {
      for (final ctrl in umbralCtrls.values) {
        ctrl.dispose();
      }
      for (final ctrl in valorCtrls.values) {
        ctrl.dispose();
      }
      for (final ctrl in descripcionCtrls.values) {
        ctrl.dispose();
      }
    });
  }

  Future<int> _secondsUntilNextOwnCounteroffer(String miUid) async {
    const cooldownMs = 30 * 1000;
    final lista = await _obtenerMensajesCompat();
    for (final msg in lista) {
      final tipo = (msg['tipo'] ?? 'contraoferta').toString();
      final remitente = (msg['remitenteUid'] ?? '').toString();
      if (tipo != 'contraoferta' || remitente != miUid) continue;
      final tsMs = _timestampToMillis(msg['timestamp']);
      if (tsMs <= 0) return 0;
      final remaining = cooldownMs - (DateTime.now().millisecondsSinceEpoch - tsMs);
      if (remaining <= 0) return 0;
      return (remaining / 1000).ceil();
    }
    return 0;
  }

  Future<List<Map<String, dynamic>>> _obtenerMensajesCompat() async {
    var lista = <Map<String, dynamic>>[];

    if (_chatId != null && _chatId!.isNotEmpty) {
      try {
        final byChat = await FirebaseFirestore.instance
            .collection('mensajes')
            .where('chatId', isEqualTo: _chatId)
            .get();
        lista = byChat.docs.map((d) => d.data()).cast<Map<String, dynamic>>().toList();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          debugPrint('Lectura mensajes por chat omitida por permisos: $e');
          return <Map<String, dynamic>>[];
        }
        rethrow;
      }
    }

    lista.sort((a, b) => _compareByTimestampDesc(a, b));
    return lista;
  }

  Future<void> _resolverColeccionActiva() async {
    final ofertaId = widget.ofertaId.trim();
    if (ofertaId.isEmpty) return;

    for (final coll in _coleccionesOferta) {
      try {
        final snap = await FirebaseFirestore.instance.collection(coll).doc(ofertaId).get();
        if (snap.exists) {
          if (_coleccionActiva != coll) {
            _coleccionActiva = coll;
            if (mounted) setState(() {});
          }
          return;
        }
      } catch (_) {}
    }
  }

  List<String> get _formasPagoPermitidas => const [
        'efectivo',
        'transferencia',
        '15dias',
        '30dias',
        '60dias',
        '90dias',
      ];

  String _sanitizePrecio(String raw) {
    final trimmed = raw.trim().replaceAll(',', '.');
    // ValidaciÃ³n bÃ¡sica; reglas especÃ­ficas por tipo se aplican al enviar
    final reg = RegExp(r'^\d{1,6}(?:\.\d{1,2})?$');
    if (trimmed.isEmpty) return '';
    return reg.hasMatch(trimmed) ? trimmed : '';
  }

  String _tipoPrecioDisplay(String tipo) {
    final t = tipo.toLowerCase().trim();
    if (t.contains('kg')) return 'â‚¬/kg';
    if (t.contains('arroba') || t.contains('@')) return 'â‚¬/@';
    if (t.contains('libra')) return 'â‚¬/libra';
    if (t.contains('unidad') || t.contains('und')) return 'â‚¬/und';
    // Fallback
    return t.replaceAll('eur_', 'â‚¬/');
  }

  String _sanitizeFormaPago(String raw) {
    final v = raw.trim().toLowerCase();
    return _formasPagoPermitidas.contains(v) ? v : '';
  }

  String _sanitizeFecha(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return '';
    final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (regex.hasMatch(r)) return r;
    final parsed = _parseDate(r);
    if (parsed == null) return '';
    return _formatDate(parsed);
  }

  DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    final raw = s.trim();
    if (raw.isEmpty) return null;

    final slashOrDash = RegExp(r'^(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})$');
    final match = slashOrDash.firstMatch(raw);
    if (match != null) {
      final day = int.tryParse(match.group(1) ?? '');
      final month = int.tryParse(match.group(2) ?? '');
      final year = int.tryParse(match.group(3) ?? '');
      if (day != null && month != null && year != null) {
        final candidate = DateTime(year, month, day);
        if (candidate.year == year && candidate.month == month && candidate.day == day) {
          return candidate;
        }
      }
    }

    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  int _compareByTimestampAsc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = _timestampToMillis(a['timestamp']);
    final tb = _timestampToMillis(b['timestamp']);
    return ta.compareTo(tb);
  }

  int _compareByTimestampDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
    final ta = _timestampToMillis(a['timestamp']);
    final tb = _timestampToMillis(b['timestamp']);
    return tb.compareTo(ta);
  }

  int _timestampToMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  bool _isPrecioInputValido(String raw) {
    if (raw.isEmpty || raw.length > 4) return false;
    final reg = RegExp(r'^\d+(?:[\.,]\d+)?$');
    return reg.hasMatch(raw);
  }

  int _cantidadDisponibleBase(Map<String, dynamic> ofertaData) {
    final raw = (ofertaData['cantidad'] ?? widget.cantidad).toString().trim();
    final parsed = int.tryParse(raw) ?? int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    return (parsed == null || parsed <= 0) ? 1 : parsed;
  }

  int _cantidadMaximaPermitida(Map<String, dynamic> ofertaData) {
    final disponible = _cantidadDisponibleBase(ofertaData);
    return disponible > 999 ? 999 : disponible;
  }

  Map<String, dynamic> _buildPenaltyRule({bool includeDescription = false}) {
    return <String, dynamic>{
      'activa': false,
      'umbral': '',
      'tipo': 'descuento',
      'valor': '',
      if (includeDescription) 'descripcion': '',
    };
  }

  Map<String, dynamic> _emptyPenalizacion() {
    return <String, dynamic>{
      'minimoIndividual': _buildPenaltyRule(),
      'minimoColectivo': _buildPenaltyRule(),
      'maximoIndividual': _buildPenaltyRule(),
      'maximoColectivo': _buildPenaltyRule(),
      'defectoAnimal': _buildPenaltyRule(includeDescription: true),
    };
  }

  String? _getSelectedPenaltyGroupKey(Map<String, bool> reglaActiva, List<String> keys) {
    for (final key in keys) {
      if (reglaActiva[key] == true) return key;
    }
    return null;
  }

  void _setSelectedPenaltyGroupKey(
    Map<String, bool> reglaActiva,
    List<String> keys,
    String? selectedKey,
  ) {
    for (final key in keys) {
      reglaActiva[key] = key == selectedKey;
    }
  }

  void _enforceExclusivePenaltyGroup(Map<String, dynamic> penalizacion, List<String> keys) {
    String? selectedKey;
    for (final key in keys) {
      final item = penalizacion[key];
      if (item is! Map) continue;
      if (item['activa'] == true) {
        selectedKey ??= key;
        if (selectedKey != key) {
          item['activa'] = false;
        }
      }
    }
  }

  String _sanitizePenaltyText(dynamic raw, {int max = 60}) {
    final value = (raw ?? '').toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (value.isEmpty) return '';
    return value.length <= max ? value : value.substring(0, max);
  }

  Map<String, dynamic> _normalizePenalizacion(dynamic raw) {
    final result = _emptyPenalizacion();
    if (raw is! Map) return result;

    for (final key in _penalizacionRuleKeys) {
      final item = raw[key];
      final base = Map<String, dynamic>.from(result[key] as Map<String, dynamic>);
      if (item is Map) {
        final tipo = _sanitizePenaltyText(item['tipo'], max: 20);
        base['activa'] = item['activa'] == true;
        base['umbral'] = _sanitizePenaltyText(item['umbral']);
        base['tipo'] = _penalizacionTypeLabels.containsKey(tipo) ? tipo : 'descuento';
        base['valor'] = _sanitizePenaltyText(item['valor']);
        if (base.containsKey('descripcion')) {
          base['descripcion'] = _sanitizePenaltyText(item['descripcion'], max: 120);
        }
      }
      result[key] = base;
    }

    _enforceExclusivePenaltyGroup(result, _penalizacionMinimoKeys);
    _enforceExclusivePenaltyGroup(result, _penalizacionMaximoKeys);
    return result;
  }

  bool _penalizacionTieneReglas(Map<String, dynamic> penalizacion) {
    for (final key in _penalizacionRuleKeys) {
      final item = penalizacion[key];
      if (item is Map && item['activa'] == true) return true;
    }
    return false;
  }

  Map<String, dynamic>? _sanitizePenalizacionPayload(dynamic raw) {
    final penalizacion = _normalizePenalizacion(raw);
    if (!_penalizacionTieneReglas(penalizacion)) return null;

    _enforceExclusivePenaltyGroup(penalizacion, _penalizacionMinimoKeys);
    _enforceExclusivePenaltyGroup(penalizacion, _penalizacionMaximoKeys);

    final cleaned = <String, dynamic>{};
    for (final key in _penalizacionRuleKeys) {
      final item = penalizacion[key];
      if (item is! Map || item['activa'] != true) continue;
      cleaned[key] = <String, dynamic>{
        'activa': true,
        'umbral': _sanitizePenaltyText(item['umbral']),
        'tipo': (_penalizacionTypeLabels.containsKey(item['tipo']) ? item['tipo'] : 'descuento'),
        'valor': _sanitizePenaltyText(item['valor']),
        if (item.containsKey('descripcion'))
          'descripcion': _sanitizePenaltyText(item['descripcion'], max: 120),
      };
    }
    return cleaned.isEmpty ? null : cleaned;
  }

  List<String> _penalizacionResumenLineas(dynamic raw) {
    final penalizacion = _sanitizePenalizacionPayload(raw);
    if (penalizacion == null) return const <String>[];

    final lineas = <String>[];
    for (final key in _penalizacionRuleKeys) {
      final item = penalizacion[key];
      if (item is! Map || item['activa'] != true) continue;
      final label = _penalizacionRuleLabels[key] ?? key;
      final tipo = _penalizacionTypeLabels[item['tipo']] ?? 'Descuento';
      final umbral = _sanitizePenaltyText(item['umbral']);
      final valor = _sanitizePenaltyText(item['valor']);
      if (key == 'defectoAnimal') {
        final descripcion = _sanitizePenaltyText(item['descripcion'], max: 120);
        final partes = <String>[];
        if (descripcion.isNotEmpty) partes.add(descripcion);
        if (tipo == 'No pagar') {
          partes.add('no se paga');
        } else if (valor.isNotEmpty) {
          partes.add('descuento $valor');
        }
        lineas.add('$label: ${partes.join(' | ')}');
      } else {
        final partes = <String>[];
        if (umbral.isNotEmpty) partes.add('umbral $umbral');
        if (tipo == 'No pagar') {
          partes.add('no se paga');
        } else if (valor.isNotEmpty) {
          partes.add('descuento $valor');
        }
        lineas.add('$label: ${partes.join(' | ')}');
      }
    }
    return lineas;
  }

  Future<bool> _registrarPenalizacionComprador(
    Map<String, dynamic>? penalizacion,
    String miUid,
  ) async {
    if (penalizacion == null) return true;

    final ofertaRef = FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId);
    final ofertaSnap = await ofertaRef.get();
    final ofertaData = ofertaSnap.data() ?? <String, dynamic>{};
    final vendedorOferta =
        (ofertaData['vendedor'] ?? ofertaData['vendedorId'] ?? ofertaData['vendedorUid'] ?? '')
            .toString()
            .trim();
    final soyVendedor = miUid.isNotEmpty && vendedorOferta.isNotEmpty && miUid == vendedorOferta;
    if (soyVendedor) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La penalizacion la propone el comprador y la revisa el vendedor.'),
          ),
        );
      }
      return false;
    }

    await ofertaRef.set(<String, dynamic>{
      'penalizacionPropuesta': penalizacion,
      'penalizacionEstado': 'pendiente',
      'penalizacionPropuestaPor': miUid,
      'penalizacionPropuestaAt': DateTime.now().toIso8601String(),
      'penalizacionRespuestaAt': FieldValue.delete(),
      'penalizacionFinal': FieldValue.delete(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<void> _notificarOtraParte({
    required String tipo,
    required String title,
    required String body,
  }) async {
    final miUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    var otroUid = (_counterpartUid ?? '').trim();
    if (otroUid.isEmpty && _chatId != null && _chatId!.isNotEmpty) {
      try {
        final chatSnap = await FirebaseFirestore.instance.collection('chats').doc(_chatId).get();
        final chatData = chatSnap.data() ?? <String, dynamic>{};
        final participants =
            (chatData['participants'] as List?)?.map((e) => e.toString()).toList() ??
                const <String>[];
        otroUid = participants.firstWhere((p) => p.isNotEmpty && p != miUid, orElse: () => '');
      } catch (_) {}
    }
    if (otroUid.isEmpty) return;
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('sendOfferPush');
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'targetUid': otroUid,
        'ofertaId': widget.ofertaId,
        'tipo': tipo,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  Future<void> _resolverSolicitudPenalizacion({required bool aceptar}) async {
    try {
      final ofertaRef =
          FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId);
      final ofertaSnap = await ofertaRef.get();
      final ofertaData = ofertaSnap.data() ?? <String, dynamic>{};
      final penalizacion = _sanitizePenalizacionPayload(ofertaData['penalizacionPropuesta']);
      if (penalizacion == null) return;

      final updates = <String, dynamic>{
        'penalizacionEstado': aceptar ? 'aceptada' : 'rechazada',
        'penalizacionRespuestaAt': DateTime.now().toIso8601String(),
      };
      if (aceptar) {
        updates['penalizacionFinal'] = penalizacion;
      } else {
        updates['penalizacionFinal'] = FieldValue.delete();
      }

      await ofertaRef.set(updates, SetOptions(merge: true));
      await _notificarOtraParte(
        tipo: aceptar ? 'penalizacion_aceptada' : 'penalizacion_rechazada',
        title: aceptar ? 'Penalizacion aceptada' : 'Penalizacion rechazada',
        body: aceptar
            ? 'El vendedor ha aceptado las condiciones de peso.'
            : 'El vendedor ha rechazado las condiciones de peso.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aceptar ? 'Penalizacion aceptada.' : 'Penalizacion rechazada.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la penalizacion: $e')),
      );
    }
  }

  Future<void> _continuarSinPenalizacion() async {
    try {
      final ofertaRef =
          FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId);
      await ofertaRef.set(<String, dynamic>{
        'penalizacionEstado': 'sin_penalizacion',
        'penalizacionPropuesta': FieldValue.delete(),
        'penalizacionFinal': FieldValue.delete(),
        'penalizacionRespuestaAt': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
      await _notificarOtraParte(
        tipo: 'penalizacion_descartada',
        title: 'Continua sin penalizacion',
        body: 'El comprador ha decidido continuar sin condiciones de peso.',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La negociacion continua sin penalizacion.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo continuar sin penalizacion: $e')),
      );
    }
  }

  String _buildPenalizacionEstadoTexto(Map<String, dynamic> ofertaData) {
    final estado = (ofertaData['penalizacionEstado'] ?? '').toString().trim();
    if (estado == 'pendiente') {
      return 'Penalizacion propuesta por el comprador. Pendiente de revision del vendedor.';
    }
    if (estado == 'aceptada') {
      return 'Penalizacion aceptada por el vendedor.';
    }
    if (estado == 'rechazada') {
      return 'El vendedor rechazo la penalizacion. Puedes seguir sin condiciones o enviar una nueva.';
    }
    if (estado == 'sin_penalizacion') {
      return 'La negociacion continua sin penalizacion.';
    }
    return '';
  }

  DateTime? _parseIsoOrNull(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _resetExpiredOfferStateIfNeeded() async {
    try {
      final ofertaSnap =
          await FirebaseFirestore.instance.collection(_coleccionActiva).doc(widget.ofertaId).get();
      if (!ofertaSnap.exists) return;
      final data = ofertaSnap.data() ?? <String, dynamic>{};
      final now = DateTime.now();
      final expirado = data['expirado'] == true;
      final ventanaExp = _parseIsoOrNull(data['ventanaTratoExpira']);
      final expiradaPorTiempo = ventanaExp != null && !now.isBefore(ventanaExp);

      if (!expirado && !expiradaPorTiempo) return;

      final callable = FirebaseFunctions.instance.httpsCallable('resetExpiredOfferState');
      await callable.call<Map<String, dynamic>>({
        'ofertaId': widget.ofertaId,
        'coleccion': _coleccionActiva,
      });
    } catch (e) {
      debugPrint('No se pudo resetear estado expirado: $e');
    }
  }
}

extension _IfEmpty on String {
  String ifEmptyUse(dynamic other) => isEmpty ? (other?.toString() ?? '') : this;
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Widget _buildBanner({required Color color, required String text, required Color textColor}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    color: color,
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
    ),
  );
}
