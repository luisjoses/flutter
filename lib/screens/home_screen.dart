import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import 'chat_list_screen.dart';
import 'tratos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const List<String> _coleccionesOferta = <String>[
    'vacas_ofertas',
    'cabras_ofertas',
    'cerdos_ofertas',
    'ovejas_ofertas',
    'otros_ofertas',
  ];

  bool tratoPendiente = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> ofertasPendientes = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> tratosCerradosComoComprador = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> tratosCerradosComoVendedor = [];
  bool _hayTratosSinLeer = false;
  Set<String> _tratoEventosActuales = <String>{};
  final Set<String> _tratoEventosLeidos = <String>{};
  String? _tratoEventosLeidosUid;
  bool _routeToastShown = false;
  Timer? _pendingRefreshTimer;
  StreamSubscription<User?>? _authSub;
  String _currentUid = '';

  @override
  void initState() {
    super.initState();
    _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final nextUid = user?.uid ?? '';
      if (nextUid == _currentUid) return;
      if (!mounted) return;
      setState(() {
        _currentUid = nextUid;
        if (_currentUid.isEmpty) {
          _hayTratosSinLeer = false;
          hayContraofertaNueva = false;
        }
      });
      if (_currentUid.isNotEmpty) {
        unawaited(checkAllPendientes());
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      checkAllPendientes();
    });
    _pendingRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      checkAllPendientes();
    });
  }

  @override
  void dispose() {
    _pendingRefreshTimer?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  // Obtiene el UID real del usuario autenticado con Firebase Auth
  String getUsuarioActualId() {
    return _currentUid;
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryEnColecciones(
    Future<QuerySnapshot<Map<String, dynamic>>> Function(CollectionReference<Map<String, dynamic>>)
        builder,
  ) async {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final coll in _coleccionesOferta) {
      try {
        final snap = await builder(FirebaseFirestore.instance.collection(coll));
        docs.addAll(snap.docs);
      } on FirebaseException catch (e) {
        // Puede ocurrir si una colección tiene reglas más restrictivas.
        if (e.code == 'permission-denied') {
          continue;
        }
        rethrow;
      }
    }
    return docs;
  }

  Future<void> checkTratoPendiente() async {
    final usuarioId = getUsuarioActualId();
    if (usuarioId.isEmpty) return;
    try {
      // Tratos en los que el vendedor aún debe aceptar
      final queryPendVendedor = await _queryEnColecciones(
        (coll) =>
            coll.where('vendedor', isEqualTo: usuarioId).where('enTrato', isEqualTo: true).get(),
      );
      // Tratos en los que el comprador aún debe aceptar
      final queryPendComprador = await _queryEnColecciones(
        (coll) =>
            coll.where('comprador', isEqualTo: usuarioId).where('enTrato', isEqualTo: true).get(),
      );
      // Tratos cerrados como comprador
      final queryCerrados = await _queryEnColecciones(
        (coll) => coll
            .where('comprador', isEqualTo: usuarioId)
            .where('aceptadoComprador', isEqualTo: true)
            .where('aceptadoVendedor', isEqualTo: true)
            .get(),
      );
      final queryCerradosVendedor = await _queryEnColecciones(
        (coll) => coll
            .where('vendedor', isEqualTo: usuarioId)
            .where('aceptadoComprador', isEqualTo: true)
            .where('aceptadoVendedor', isEqualTo: true)
            .get(),
      );

      // La liberación/normalización de tratos se resuelve en backend (Cloud Functions + reglas).
      // Aquí solo filtramos para UI y evitamos escrituras cliente con permisos restringidos.

      if (!mounted) return;
      final now = DateTime.now();
      final pendientesVendedor = queryPendVendedor.where((d) {
        final data = d.data();
        return _isPendingPartialActive(data, now) && data['aceptadoVendedor'] != true;
      }).toList();
      final pendientesComprador = queryPendComprador.where((d) {
        final data = d.data();
        return _isPendingPartialActive(data, now) && data['aceptadoComprador'] != true;
      }).toList();
      final pendientesActivasByPath = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{
        for (final d in [...pendientesVendedor, ...pendientesComprador]) d.reference.path: d,
      };
      final pendientesFiltradas = pendientesActivasByPath.values.toList();
      final cerradosFiltradas = queryCerrados.where((d) {
        final data = d.data();
        return data['expirado'] != true;
      }).toList();
      final cerradosComoVendedorFiltradas = queryCerradosVendedor.where((d) {
        final data = d.data();
        return data['expirado'] != true;
      }).toList();
      final nextOfertasPendientes = _sortedByRecent(pendientesFiltradas);
      final nextCerradosComprador = _sortedByRecent(cerradosFiltradas);
      final nextCerradosVendedor = _sortedByRecent(cerradosComoVendedorFiltradas);
      final nextTratoKeys = _collectTratoEventKeys(
          nextOfertasPendientes, nextCerradosComprador, nextCerradosVendedor);
      await _cargarTratosLeidos(usuarioId, nextTratoKeys);
      final hayNovedadTrato = nextTratoKeys.any((k) => !_tratoEventosLeidos.contains(k));

      setState(() {
        tratoPendiente = pendientesFiltradas.isNotEmpty;
        ofertasPendientes = nextOfertasPendientes;
        tratosCerradosComoComprador = nextCerradosComprador;
        tratosCerradosComoVendedor = nextCerradosVendedor;
        _tratoEventosActuales = nextTratoKeys;
        if (_tratoEventosActuales.isEmpty) {
          _hayTratosSinLeer = false;
        } else if (hayNovedadTrato) {
          _hayTratosSinLeer = true;
        }
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        return;
      }
      print('Error consultando tratos pendientes: $e');
    } catch (e) {
      print('Error consultando tratos pendientes: $e');
    }
  }

  // Ya existe una definición de initState y didChangeDependencies arriba, así que eliminamos estas duplicadas.

  bool hayContraofertaNueva = false;

  Future<void> checkContraofertaNueva() async {
    final usuarioId = getUsuarioActualId();
    if (usuarioId.isEmpty) return;
    try {
      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: usuarioId)
          .get();
      final nuevos = chatQuery.docs.isNotEmpty ||
          chatQuery.docs.any((doc) {
            final data = doc.data();
            final unreadFor = (data['unreadFor'] as List?)?.map((e) => e.toString()).toList() ?? [];
            return unreadFor.contains(usuarioId);
          });
      if (!mounted) return;
      setState(() {
        hayContraofertaNueva = nuevos;
      });
    } catch (_) {}
  }

  // Eliminadas las definiciones duplicadas de initState y didChangeDependencies

  Future<void> checkAllPendientes() async {
    await checkTratoPendiente();
    await checkContraofertaNueva();
  }

  void _mostrarDialogoIdioma(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final localeActual = Localizations.localeOf(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.t('selectLanguage')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: supportedLocales.map((locale) {
            final seleccionado = locale.languageCode == localeActual.languageCode;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                seleccionado ? Icons.radio_button_checked : Icons.radio_button_off,
                color: const Color(0xFF004d26),
              ),
              title: Text(
                locale.languageCode == 'es' ? loc.t('spanish') : loc.t('portuguese'),
              ),
              onTap: () {
                MyApp.of(context)?.setLocale(locale);
                Navigator.pop(dialogContext);
                if (mounted) {
                  setState(() {});
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  DateTime? _asDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _isSingleSideAccepted(Map<String, dynamic> data) {
    final aceptadoComprador = data['aceptadoComprador'] == true;
    final aceptadoVendedor = data['aceptadoVendedor'] == true;
    return aceptadoComprador != aceptadoVendedor;
  }

  DateTime? _pendingExpiry(Map<String, dynamic> data) {
    final expira = _asDateTime(data['ventanaTratoExpira']);
    if (expira != null) return expira;
    final inicio = _asDateTime(data['ventanaTratoInicio']);
    if (inicio != null) return inicio.add(const Duration(hours: 24));
    return null;
  }

  bool _isPendingPartialActive(Map<String, dynamic> data, DateTime now) {
    if (data['expirado'] == true) return false;
    if (!_isSingleSideAccepted(data)) return false;
    final expira = _pendingExpiry(data);
    if (expira == null) return true;
    return now.isBefore(expira);
  }

  int _docRecentMillis(Map<String, dynamic> data) {
    final closeDate = _asDateTime(data['fechaCierreTrato']);
    if (closeDate != null) return closeDate.millisecondsSinceEpoch;

    final pendingStart = _asDateTime(data['ventanaTratoInicio']);
    if (pendingStart != null) return pendingStart.millisecondsSinceEpoch;

    final updated = _asDateTime(data['updatedAt']);
    if (updated != null) return updated.millisecondsSinceEpoch;

    final created = _asDateTime(data['createdAt']);
    if (created != null) return created.millisecondsSinceEpoch;

    return 0;
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedByRecent(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sorted = [...docs];
    sorted.sort((a, b) {
      final ma = _docRecentMillis(a.data());
      final mb = _docRecentMillis(b.data());
      return mb.compareTo(ma);
    });
    return sorted;
  }

  String _tratoEventKey(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final isClosed = data['vendido'] == true ||
        (data['aceptadoComprador'] == true && data['aceptadoVendedor'] == true) ||
        _asDateTime(data['fechaCierreTrato']) != null;
    final stamp = _docRecentMillis(data);
    final state = isClosed ? 'closed' : 'pending';
    return '${doc.reference.path}|$state|$stamp';
  }

  String _tratosLeidosPrefsKey(String uid) => 'home.tratos.leidos.$uid';

  Future<void> _cargarTratosLeidos(String uid, Set<String> baselineActual) async {
    if (_tratoEventosLeidosUid == uid) return;

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_tratosLeidosPrefsKey(uid)) ?? <String>[];
    _tratoEventosLeidos
      ..clear()
      ..addAll(saved);

    // Primera carga de este usuario: no marcar en rojo tratos históricos ya existentes.
    if (saved.isEmpty && baselineActual.isNotEmpty) {
      _tratoEventosLeidos.addAll(baselineActual);
      await prefs.setStringList(_tratosLeidosPrefsKey(uid), _tratoEventosLeidos.toList());
    }

    _tratoEventosLeidosUid = uid;
  }

  Future<void> _guardarTratosLeidos(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_tratosLeidosPrefsKey(uid), _tratoEventosLeidos.toList());
  }

  Set<String> _collectTratoEventKeys(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendientes,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> cerradosComprador,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> cerradosVendedor,
  ) {
    final keys = <String>{};
    for (final d in [...pendientes, ...cerradosComprador, ...cerradosVendedor]) {
      keys.add(_tratoEventKey(d));
    }
    return keys;
  }

  Future<void> _marcarTratosComoLeidos() async {
    _tratoEventosLeidos.addAll(_tratoEventosActuales);
    _hayTratosSinLeer = false;

    final uid = getUsuarioActualId();
    if (uid.isNotEmpty) {
      await _guardarTratosLeidos(uid);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (!_routeToastShown && args is Map) {
      String? msg;
      final loc = AppLocalizations.of(context);
      if (args['toastKey'] is String) {
        final key = args['toastKey'] as String;
        final Map<String, String>? targs = args['toastArgs'] is Map
            ? (args['toastArgs'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null;
        msg = targs == null ? loc.t(key) : loc.tf(key, targs);
      } else if (args['toast'] is String) {
        msg = args['toast'] as String;
      }
      if (msg != null && msg.isNotEmpty) {
        _routeToastShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg!)));
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF004d26),
        elevation: 0,
        leadingWidth: 44,
        leading: Builder(
          builder: (context) {
            final uid = getUsuarioActualId();
            return _UnreadContactLogo(
              uid: uid,
              onTap: () {
                if (uid.isEmpty) return;
                setState(() {
                  hayContraofertaNueva = false;
                });
                Navigator.push<Widget>(
                  context,
                  MaterialPageRoute<Widget>(builder: (_) => const ChatListScreen()),
                );
              },
            );
          },
        ),
        centerTitle: true,
        title: Image.asset(
          'assets/images/logo.png',
          height: 40,
          fit: BoxFit.contain,
          alignment: Alignment.center,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.handshake,
                color: _hayTratosSinLeer ? Colors.red : Colors.white, size: 32),
            onPressed: () async {
              await _marcarTratosComoLeidos();
              if (mounted) {
                setState(() {});
              }
              await Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (_) => const TratosScreen()),
              );
              if (!mounted) return;
              await checkAllPendientes();
            },
            tooltip: 'Tratos',
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.menu, color: Colors.white),
            onSelected: (value) {
              if (value == 0) {
                // Perfil
                Navigator.pushNamed(context, '/perfil');
              } else if (value == 1) {
                // Mis ofertas
                Navigator.pushNamed(context, '/mis-ofertas');
              } else if (value == 2) {
                // Idioma
                _mostrarDialogoIdioma(context);
              } else if (value == 3) {
                // Contacto
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(loc.t('contact').split(':').first),
                    content: Text(loc.t('contact').split(':').length > 1
                        ? loc.t('contact').split(':')[1].trim()
                        : 'bysapp@hotmail.com'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              } else if (value == 4) {
                // Cerrar sesión
                FirebaseAuth.instance.signOut().then((_) {
                  if (!context.mounted) return;
                  Navigator.pushReplacementNamed(context, '/login');
                });
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 0,
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(loc.t('profile')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 1,
                child: Row(
                  children: [
                    const Icon(Icons.local_offer, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(loc.t('myOffers')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 2,
                child: Row(
                  children: [
                    const Icon(Icons.language, color: Colors.black54),
                    const SizedBox(width: 8),
                    Text(loc.t('language')),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 3,
                child: Row(
                  children: [
                    const Icon(Icons.email, color: Colors.black54),
                    const SizedBox(width: 8),
                    Flexible(child: Text(loc.t('contact'))),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 4,
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.red),
                    const SizedBox(width: 8),
                    Text(loc.t('closeSession'), style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
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
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 32),
                  Text(loc.t('whatDoYouWant'),
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 32),
                  Container(
                    width: 260,
                    height: 100,
                    margin: const EdgeInsets.only(bottom: 32),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.65),
                      borderRadius: BorderRadius.zero,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 200,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/comprar');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004d26),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: Text(loc.t('buy'),
                              style: const TextStyle(fontSize: 22, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 260,
                    height: 100,
                    margin: const EdgeInsets.only(),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.65),
                      borderRadius: BorderRadius.zero,
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 200,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/vender');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004d26),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                          child: Text(loc.t('sell'),
                              style: const TextStyle(fontSize: 22, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ), // Padding
          ), // Center
        ], // Stack children
      ), // Stack
    ); // Scaffold
  } // build
} // HomeScreen

// _buildAnimalButton eliminado por no usarse

/// Widget que escucha 3 streams de Firestore (participants, vendedorId, compradorId)
/// y muestra logocontacto.png en rojo cuando hay mensajes sin leer.
class _UnreadContactLogo extends StatefulWidget {
  final String uid;
  final VoidCallback onTap;

  const _UnreadContactLogo({required this.uid, required this.onTap});

  @override
  State<_UnreadContactLogo> createState() => _UnreadContactLogoState();
}

class _UnreadContactLogoState extends State<_UnreadContactLogo> {
  bool _hasUnread = false;
  final List<StreamSubscription<QuerySnapshot>> _subs = [];
  final Map<int, bool> _queryHasUnread = {0: false, 1: false, 2: false};

  @override
  void initState() {
    super.initState();
    _subscribeToStreams();
  }

  void _subscribeToStreams() {
    final uid = widget.uid;
    if (uid.isEmpty) {
      _clearSubscriptions();
      if (_hasUnread) {
        setState(() => _hasUnread = false);
      }
      return;
    }
    final db = FirebaseFirestore.instance;
    final queries = <Stream<QuerySnapshot>>[
      db.collection('chats').where('participants', arrayContains: uid).snapshots(),
      db.collection('chats').where('vendedorId', isEqualTo: uid).snapshots(),
      db.collection('chats').where('compradorId', isEqualTo: uid).snapshots(),
    ];
    for (var i = 0; i < queries.length; i++) {
      final idx = i;
      final sub = queries[i].listen((snapshot) {
        bool anyUnread = false;
        for (final d in snapshot.docs) {
          final data = d.data() as Map<String, dynamic>;
          final unreadFor = (data['unreadFor'] as List?)?.map((e) => e.toString()).toList() ?? [];
          if (unreadFor.contains(uid)) {
            anyUnread = true;
            break;
          }
        }
        if (_queryHasUnread[idx] != anyUnread) {
          _queryHasUnread[idx] = anyUnread;
          final combined = _queryHasUnread.values.any((v) => v);
          if (mounted && combined != _hasUnread) {
            setState(() => _hasUnread = combined);
          }
        }
      });
      _subs.add(sub);
    }
  }

  @override
  void didUpdateWidget(covariant _UnreadContactLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid == widget.uid) return;
    _clearSubscriptions();
    _queryHasUnread.updateAll((_, __) => false);
    _subscribeToStreams();
  }

  void _clearSubscriptions() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  @override
  void dispose() {
    _clearSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          Icons.chat,
          color: _hasUnread ? Colors.red : Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
