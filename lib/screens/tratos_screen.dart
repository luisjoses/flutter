import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import 'trato_detalle_screen.dart';

class TratosScreen extends StatefulWidget {
  const TratosScreen({super.key});

  @override
  State<TratosScreen> createState() => _TratosScreenState();
}

class _TratosScreenState extends State<TratosScreen> {
  static const List<String> _colecciones = <String>[
    'vacas_ofertas',
    'cabras_ofertas',
    'cerdos_ofertas',
    'ovejas_ofertas',
    'otros_ofertas',
  ];

  late Future<List<_DealItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDeals();
  }

  Future<List<_DealItem>> _loadDeals() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return <_DealItem>[];

    final byPath = <String, _DealItem>{};

    for (final coll in _colecciones) {
      final ref = FirebaseFirestore.instance.collection(coll);
      try {
        final vendedorSnap =
            await ref.where('vendedor', isEqualTo: uid).where('enTrato', isEqualTo: true).get();
        for (final d in vendedorSnap.docs) {
          byPath[d.reference.path] = _buildItem(d, uid, coll);
        }
      } on FirebaseException catch (_) {}

      try {
        final compradorSnap =
            await ref.where('comprador', isEqualTo: uid).where('enTrato', isEqualTo: true).get();
        for (final d in compradorSnap.docs) {
          byPath[d.reference.path] = _buildItem(d, uid, coll);
        }
      } on FirebaseException catch (_) {}

      try {
        final cerradosVendedor = await ref
            .where('vendedor', isEqualTo: uid)
            .where('aceptadoComprador', isEqualTo: true)
            .where('aceptadoVendedor', isEqualTo: true)
            .get();
        for (final d in cerradosVendedor.docs) {
          byPath[d.reference.path] = _buildItem(d, uid, coll);
        }
      } on FirebaseException catch (_) {}

      try {
        final cerradosComprador = await ref
            .where('comprador', isEqualTo: uid)
            .where('aceptadoComprador', isEqualTo: true)
            .where('aceptadoVendedor', isEqualTo: true)
            .get();
        for (final d in cerradosComprador.docs) {
          byPath[d.reference.path] = _buildItem(d, uid, coll);
        }
      } on FirebaseException catch (_) {}
    }

    final items = byPath.values.toList();
    items.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    return items;
  }

  _DealItem _buildItem(QueryDocumentSnapshot<Map<String, dynamic>> doc, String uid, String coll) {
    final data = doc.data();
    final vendedor =
        (data['vendedor'] ?? data['vendedorId'] ?? data['vendedorUid'] ?? '').toString();
    final comprador =
        (data['comprador'] ?? data['compradorId'] ?? data['compradorUid'] ?? '').toString();
    final isSeller = vendedor.isNotEmpty && vendedor == uid;
    final isBuyer = comprador.isNotEmpty && comprador == uid;
    final closed = data['vendido'] == true ||
        (data['aceptadoComprador'] == true && data['aceptadoVendedor'] == true) ||
        _parseDate(data['fechaCierreTrato']) != null;

    final sortDate = _parseDate(data['fechaCierreTrato']) ??
        _parseDate(data['ventanaTratoInicio']) ??
        _parseDate(data['updatedAt']) ??
        _parseDate(data['createdAt']);

    final role = isSeller ? 'vendedor' : (isBuyer ? 'comprador' : 'participante');

    return _DealItem(
      id: doc.id,
      collection: coll,
      data: data,
      role: role,
      isClosed: closed,
      sortMillis: sortDate?.millisecondsSinceEpoch ?? 0,
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  Future<void> _refresh() async {
    final f = _loadDeals();
    setState(() => _future = f);
    await f;
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              bilingual
                  ? AppLocalizations.bilingual('dealsAndClosedTitle')
                  : loc.t('dealsAndClosedTitle'),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_DealItem>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? <_DealItem>[];
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                        bilingual ? AppLocalizations.bilingual('noMessages') : loc.t('noMessages')),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final data = item.data;
                      final raza = (data['raza'] ?? '').toString();
                      final cantidad = (data['cantidad'] ?? '').toString();
                      final precio = (data['precioFinal'] ?? data['precio'] ?? '').toString();
                      final tipoPrecio =
                          (data['tipoPrecio'] ?? '').toString().replaceAll('eur_', 'â‚¬/');
                      final title = '$raza â€¢ $cantidad â€¢ $precio $tipoPrecio';
                      final subtitle = item.isClosed
                          ? (bilingual
                              ? AppLocalizations.bilingual('dealClosed')
                              : loc.t('dealClosed'))
                          : (bilingual
                              ? AppLocalizations.bilingual('dealPending')
                              : loc.t('dealPending'));

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              item.isClosed ? Colors.blueGrey : const Color(0xFF004d26),
                          child: Icon(item.isClosed ? Icons.check : Icons.handshake,
                              color: Colors.white, size: 18),
                        ),
                        title: Text(title),
                        subtitle: Text('$subtitle â€¢ ${item.role}'),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => TratoDetalleScreen(
                                docId: item.id,
                                collection: item.collection,
                                data: item.data,
                                role: item.role,
                                isClosed: item.isClosed,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DealItem {
  _DealItem({
    required this.id,
    required this.collection,
    required this.data,
    required this.role,
    required this.isClosed,
    required this.sortMillis,
  });

  final String id;
  final String collection;
  final Map<String, dynamic> data;
  final String role;
  final bool isClosed;
  final int sortMillis;
}
