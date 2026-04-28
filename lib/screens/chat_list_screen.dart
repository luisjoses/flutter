import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import 'chat_contraoferta_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final Map<String, Future<String>> _buyerAliasFutureCache = <String, Future<String>>{};
  final Map<String, Future<Map<String, String>>> _offerPreviewFutureCache =
      <String, Future<Map<String, String>>>{};
  final Map<String, Future<List<_ChatHistoryEntry>>> _callableEntriesFutureCache =
      <String, Future<List<_ChatHistoryEntry>>>{};

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final loc = AppLocalizations.of(context);
    final bilingual = MyApp.of(context)?.bilingualMode ?? false;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: const Center(child: Text('No autenticado')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
        centerTitle: true,
        backgroundColor: const Color(0xFF004d26),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Text(
              'CONTRAOFERTAS',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildCallableFallback(uid, loc, bilingual);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return _buildCallableFallback(uid, loc, bilingual);
                }
                final entries = docs
                    .map((doc) => _entryFromChatDoc(doc.id, doc.data()))
                    .whereType<_ChatHistoryEntry>()
                    .toList()
                  ..sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
                if (entries.isEmpty) {
                  return _buildCallableFallback(uid, loc, bilingual);
                }
                return _buildChatList(context, entries, uid, loc, bilingual);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallableFallback(String uid, AppLocalizations loc, bool bilingual) {
    final future = _callableEntriesFutureCache.putIfAbsent(uid, () => _loadEntriesViaCallable(uid));
    return FutureBuilder<List<_ChatHistoryEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data ?? <_ChatHistoryEntry>[];
        if (entries.isEmpty) {
          return Center(
            child: Text(
              bilingual ? AppLocalizations.bilingual('noMessages') : loc.t('noMessages'),
              style: const TextStyle(color: Colors.grey),
            ),
          );
        }
        return _buildChatList(context, entries, uid, loc, bilingual);
      },
    );
  }

  Future<List<_ChatHistoryEntry>> _loadEntriesViaCallable(String uid) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('listMyChats');
      final response = await callable.call<Map<String, dynamic>>();
      final data = response.data;
      final rawChats = (data['chats'] as List?) ?? const <dynamic>[];
      final entries = rawChats
          .map((raw) {
            if (raw is! Map) return null;
            final chatId = (raw['chatId'] ?? '').toString().trim();
            final payload =
                Map<String, dynamic>.from(raw['data'] as Map? ?? const <String, dynamic>{});
            return _entryFromChatDoc(chatId, payload);
          })
          .whereType<_ChatHistoryEntry>()
          .toList()
        ..sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
      return entries;
    } catch (_) {
      return <_ChatHistoryEntry>[];
    }
  }

  _ChatHistoryEntry? _entryFromChatDoc(String chatId, Map<String, dynamic> data) {
    final ofertaId = (data['ofertaId'] ?? '').toString().trim();
    if (ofertaId.isEmpty) return null;
    final unreadFor = (data['unreadFor'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
    return _ChatHistoryEntry(
      key: 'chat:$chatId',
      chatId: chatId,
      ofertaId: ofertaId,
      coleccion: (data['coleccion'] ?? 'vacas_ofertas').toString(),
      vendedorId: (data['vendedorId'] ?? '').toString(),
      tipoPrecio: (data['tipoPrecio'] ?? '').toString(),
      formaPago: (data['formaPago'] ?? '').toString(),
      fechaSalida: (data['fecha'] ?? '').toString(),
      precioInicial: double.tryParse((data['precio'] ?? '0').toString()) ?? 0,
      raza: (data['raza'] ?? '').toString(),
      cantidad: (data['cantidad'] ?? '').toString(),
      hasUnread: unreadFor.contains(FirebaseAuth.instance.currentUser?.uid ?? ''),
      sortMillis: _timestampToMillis(data['lastMessageTimestamp']) == 0
          ? (_timestampToMillis(data['createdAt']) == 0
              ? int.tryParse((data['createdAtMillis'] ?? '0').toString()) ?? 0
              : _timestampToMillis(data['createdAt']))
          : (_timestampToMillis(data['lastMessageTimestamp']) == 0
              ? int.tryParse((data['lastMessageTimestampMillis'] ?? '0').toString()) ?? 0
              : _timestampToMillis(data['lastMessageTimestamp'])),
      rawData: data,
    );
  }

  Widget _buildChatList(
    BuildContext context,
    List<_ChatHistoryEntry> entries,
    String uid,
    AppLocalizations loc,
    bool bilingual,
  ) {
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final data = entry.rawData;
        final hasUnread = entry.hasUnread;
        final vendedorId = entry.vendedorId;
        final isSeller = vendedorId.isNotEmpty && vendedorId == uid;
        return FutureBuilder<_ChatPreviewData>(
          future: _resolvePreviewData(data, uid),
          builder: (context, previewSnap) {
            final preview = previewSnap.data ?? const _ChatPreviewData();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: hasUnread ? const Color(0xFFFFE5E5) : const Color(0xFFF7F4F4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hasUnread ? const Color(0xFFFFB3B3) : const Color(0xFFE7DFDF),
                ),
              ),
              child: ListTile(
                leading: _buildLeading(preview, hasUnread, isSeller),
                title: Text(
                  preview.title.isEmpty ? (isSeller ? 'Comprador' : 'Oferta') : preview.title,
                  style: TextStyle(fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w500),
                ),
                subtitle: Text(preview.subtitle.isNotEmpty
                    ? preview.subtitle
                    : '${entry.formaPago} â€¢ ${entry.fechaSalida}'),
                onTap: () async {
                  final counterpartUid = _extractCounterpartUid(data, uid);
                  if (entry.chatId.isNotEmpty) {
                    try {
                      await FirebaseFirestore.instance
                          .collection('chats')
                          .doc(entry.chatId)
                          .update({
                        'unreadFor': FieldValue.arrayRemove([uid]),
                      });
                    } catch (_) {}
                  }
                  await Navigator.push<Widget>(
                    context,
                    MaterialPageRoute<Widget>(
                      builder: (_) => ChatContraofertaScreen(
                        chatId: entry.chatId,
                        counterpartUid: counterpartUid,
                        ofertaId: entry.ofertaId,
                        coleccion: entry.coleccion,
                        vendedorId: entry.vendedorId,
                        tipoPrecio: entry.tipoPrecio,
                        formaPago: entry.formaPago,
                        fechaSalida: entry.fechaSalida,
                        precioInicial: entry.precioInicial,
                        raza: entry.raza,
                        cantidad: entry.cantidad,
                      ),
                    ),
                  );
                  // Invalidar cachÃ© del callable para que la lista se refresque con estado de leÃ­do actualizado
                  setState(() {
                    _callableEntriesFutureCache.remove(uid);
                  });
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLeading(_ChatPreviewData preview, bool hasUnread, bool isSeller) {
    final base = preview.imageUrl.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Image.network(preview.imageUrl, fit: BoxFit.cover),
            ),
          )
        : CircleAvatar(
            backgroundColor: isSeller ? const Color(0xFF004d26) : const Color(0xFFE0E0E0),
            child: Icon(isSeller ? Icons.person : Icons.image_not_supported,
                color: isSeller ? Colors.white : Colors.grey),
          );

    return Stack(
      children: [
        base,
        if (hasUnread)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Future<_ChatPreviewData> _resolvePreviewData(Map<String, dynamic> data, String myUid) async {
    final vendedorId = (data['vendedorId'] ?? '').toString();
    final isSeller = vendedorId.isNotEmpty && vendedorId == myUid;
    final offer = await _getOfferPreview(data);
    final offerTitle = (offer['titulo'] ?? data['titulo'] ?? data['raza'] ?? '').toString().trim();
    final offerImage = (offer['foto'] ?? '').toString();

    if (isSeller) {
      final buyerUid = _extractBuyerUid(data, vendedorId);
      final buyerAlias = buyerUid.isEmpty ? '' : await _getBuyerAlias(buyerUid);
      return _ChatPreviewData(
        title: buyerAlias.isEmpty ? 'Comprador' : buyerAlias,
        subtitle: offerTitle,
        imageUrl: offerImage,
      );
    }

    final fallbackTitle = (data['titulo'] ?? data['raza'] ?? '').toString().trim();
    return _ChatPreviewData(
      title: offer['titulo'] ?? fallbackTitle,
      imageUrl: offer['foto'] ?? '',
      subtitle: '${data['formaPago'] ?? ''} â€¢ ${data['fecha'] ?? ''}',
    );
  }

  String _extractBuyerUid(Map<String, dynamic> data, String vendedorId) {
    final compradorId = (data['compradorId'] ?? data['comprador'] ?? '').toString().trim();
    if (compradorId.isNotEmpty && compradorId != vendedorId) {
      return compradorId;
    }
    final rawParticipants = data['participants'];
    final participants = rawParticipants is Iterable
        ? rawParticipants.map((e) => e.toString()).toList()
        : <String>[];
    for (final participant in participants) {
      if (participant.isNotEmpty && participant != vendedorId) {
        return participant;
      }
    }
    return (data['compradorId'] ?? data['comprador'] ?? '').toString();
  }

  Future<String> _getBuyerAlias(String uid) {
    return _buyerAliasFutureCache.putIfAbsent(uid, () async {
      try {
        final snapUsuarios = await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
        final dataUsuarios = snapUsuarios.data();
        if (snapUsuarios.exists && dataUsuarios != null) {
          return _buildBuyerAlias(dataUsuarios, uid);
        }
        final snapUsuario = await FirebaseFirestore.instance.collection('usuario').doc(uid).get();
        final dataUsuario = snapUsuario.data();
        if (snapUsuario.exists && dataUsuario != null) {
          return _buildBuyerAlias(dataUsuario, uid);
        }
        return _buildBuyerAlias(<String, dynamic>{}, uid);
      } catch (_) {
        return _buildBuyerAlias(<String, dynamic>{}, uid);
      }
    });
  }

  String _buildBuyerAlias(Map<String, dynamic> userData, String uid) {
    final nombre = (userData['nombre'] ?? '').toString().trim();
    final idDoc = (userData['dni'] ?? userData['cif'] ?? '').toString().toUpperCase();

    final firstLetterMatch = RegExp(r'[A-Za-z]').firstMatch(nombre);
    final firstLetter = firstLetterMatch != null ? firstLetterMatch.group(0)!.toUpperCase() : 'X';

    final digits = RegExp(r'\d').allMatches(idDoc).map((m) => m.group(0)!).join();
    final lastTwoDigits =
        digits.length >= 2 ? digits.substring(digits.length - 2) : digits.padLeft(2, '0');

    final letterMatches = RegExp(r'[A-Z]').allMatches(idDoc).toList();
    final uidSuffix =
        uid.length <= 4 ? uid.toUpperCase() : uid.substring(uid.length - 4).toUpperCase();

    if (letterMatches.isEmpty && digits.isEmpty) {
      if (nombre.isEmpty) {
        return 'Comprador $uidSuffix';
      }
      return 'Comprador $firstLetter$uidSuffix';
    }

    final lastLetter = letterMatches.isNotEmpty ? letterMatches.last.group(0)! : uidSuffix;

    return 'Comprador $firstLetter$lastTwoDigits$lastLetter';
  }

  String _extractCounterpartUid(Map<String, dynamic> data, String myUid) {
    final vendedorId = (data['vendedorId'] ?? data['vendedor'] ?? '').toString().trim();
    if (vendedorId.isNotEmpty && vendedorId != myUid) {
      return vendedorId;
    }

    final compradorId = (data['compradorId'] ?? data['comprador'] ?? '').toString().trim();
    if (compradorId.isNotEmpty && compradorId != myUid) {
      return compradorId;
    }

    final rawParticipants = data['participants'];
    final participants = rawParticipants is Iterable
        ? rawParticipants.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    for (final participant in participants) {
      if (participant != myUid) {
        return participant;
      }
    }
    return '';
  }

  Future<Map<String, String>> _getOfferPreview(Map<String, dynamic> data) {
    final ofertaId = (data['ofertaId'] ?? '').toString().trim();
    final coleccion = (data['coleccion'] ?? 'vacas_ofertas').toString();
    if (ofertaId.isEmpty) {
      return Future<Map<String, String>>.value(<String, String>{});
    }

    final cacheKey = '$coleccion|$ofertaId';
    return _offerPreviewFutureCache.putIfAbsent(cacheKey, () async {
      try {
        final snap = await FirebaseFirestore.instance.collection(coleccion).doc(ofertaId).get();
        if (!snap.exists) return <String, String>{};

        final offerData = snap.data() ?? <String, dynamic>{};
        final fotos = offerData['fotos'];
        String foto = '';
        if (fotos is List && fotos.isNotEmpty) {
          foto = fotos.first.toString();
        }

        final titulo = (offerData['titulo'] ?? offerData['raza'] ?? '').toString().trim();
        return <String, String>{'foto': foto, 'titulo': titulo};
      } catch (_) {
        return <String, String>{};
      }
    });
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
}

class _ChatPreviewData {
  final String title;
  final String imageUrl;
  final String subtitle;

  const _ChatPreviewData({this.title = '', this.imageUrl = '', this.subtitle = ''});
}

class _ChatHistoryEntry {
  final String key;
  final String chatId;
  final String ofertaId;
  final String coleccion;
  final String vendedorId;
  final String tipoPrecio;
  final String formaPago;
  final String fechaSalida;
  final double precioInicial;
  final String raza;
  final String cantidad;
  final bool hasUnread;
  final int sortMillis;
  final Map<String, dynamic> rawData;

  const _ChatHistoryEntry({
    required this.key,
    required this.chatId,
    required this.ofertaId,
    required this.coleccion,
    required this.vendedorId,
    required this.tipoPrecio,
    required this.formaPago,
    required this.fechaSalida,
    required this.precioInicial,
    required this.raza,
    required this.cantidad,
    required this.hasUnread,
    required this.sortMillis,
    required this.rawData,
  });
}
