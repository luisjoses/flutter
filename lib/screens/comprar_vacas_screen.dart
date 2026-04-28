import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'detalle_oferta_screen.dart';

class ComprarVacasScreen extends StatelessWidget {
  const ComprarVacasScreen({super.key});

  // Estructura para CP y coordenadas
  Future<Map<String, List<double>>> cargarCPsCoords() async {
    final csv = await rootBundle.loadString('assets/cp_coords_es.csv');
    final lines = LineSplitter.split(csv).where((l) => l.isNotEmpty && !l.startsWith('#'));
    final map = <String, List<double>>{};
    bool isHeader = true;
    for (var line in lines) {
      // Saltar la cabecera
      if (isHeader) {
        isHeader = false;
        continue;
      }
      // Usar punto y coma como separador principal
      final parts = line.split(';');
      if (parts.length >= 5) {
        final String cp = parts[2].trim();
        final String latStr = parts[3].trim().replaceAll(',', '.');
        final String lonStr = parts[4].trim().replaceAll(',', '.');
        final double lat = double.tryParse(latStr) ?? 0;
        final double lon = double.tryParse(lonStr) ?? 0;
        map[cp] = [lat, lon];
        // Evitar spam: sÃ³lo contamos coordenadas invÃ¡lidas para un log resumido
      }
    }
    // (Log resumido) PodrÃ­as almacenar conteo si se necesita
    return map;
  }

  double haversine(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371; // Radio de la tierra en km
    final dLat = (lat2 - lat1) * 3.141592653589793 / 180;
    final dLon = (lon2 - lon1) * 3.141592653589793 / 180;
    final a = (sin(dLat / 2) * sin(dLat / 2)) +
        cos(lat1 * 3.141592653589793 / 180) *
            cos(lat2 * 3.141592653589793 / 180) *
            (sin(dLon / 2) * sin(dLon / 2));
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController _cantidadMinController = TextEditingController();
    final TextEditingController _cpController = TextEditingController();
    final TextEditingController _radioController = TextEditingController();
    String? _razaFiltro;
    final ValueNotifier<bool> _showFilters = ValueNotifier(false);
    final ValueNotifier<Map<String, dynamic>> _filtros = ValueNotifier({});

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
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              _showFilters.value = !_showFilters.value;
            },
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
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: _showFilters,
                  builder: (context, show, _) {
                    if (!show) return const SizedBox.shrink();
                    return Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        border: Border.all(color: const Color(0xFF004d26), width: 2),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Filtrar ofertas',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF004d26))),
                          const SizedBox(height: 12),
                          // Eliminado campo precio mÃ­nimo
                          TextField(
                            controller: _cantidadMinController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Cantidad mÃ­nima',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _cpController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'CÃ³digo Postal',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _radioController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Radio (km)',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            decoration: InputDecoration(
                              labelText: 'Raza',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: const [
                              DropdownMenuItem(child: Text('Todas')), // opciÃ³n por defecto
                              DropdownMenuItem(value: 'Limousin', child: Text('Limousin')),
                              DropdownMenuItem(value: 'Charolais', child: Text('Charolais')),
                              DropdownMenuItem(value: 'Retinta', child: Text('Retinta')),
                              DropdownMenuItem(value: 'AvileÃ±a', child: Text('AvileÃ±a')),
                              DropdownMenuItem(value: 'Otra', child: Text('Otra')),
                            ],
                            value: _razaFiltro,
                            onChanged: (value) {
                              _razaFiltro = value;
                            },
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check),
                                label: const Text('Aplicar'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF004d26),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: () {
                                  _filtros.value = {
                                    'cantidadMin': _cantidadMinController.text,
                                    'raza': _razaFiltro,
                                    'cp': _cpController.text,
                                    'radio': _radioController.text,
                                  };
                                  _showFilters.value = false;
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Expanded(
                  child: ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: _filtros,
                    builder: (context, filtros, _) {
                      return FutureBuilder<Map<String, List<double>>>(
                        future: cargarCPsCoords(),
                        builder: (context, cpSnapshot) {
                          if (cpSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final cpCoords = cpSnapshot.data ?? {};
                          return FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance.collection('vacas_ofertas').get(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (snapshot.hasError) {
                                return Text('Error al cargar ofertas: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.red));
                              }
                              final docs = snapshot.data?.docs ?? [];
                              // Filtrado local con distancia
                              final cantidadMin =
                                  int.tryParse((filtros['cantidadMin'] ?? '').toString()) ?? 0;
                              final razaFiltro = filtros['raza'];
                              String cpFiltro = filtros['cp']?.toString() ?? '';
                              final radioFiltro =
                                  double.tryParse((filtros['radio'] ?? '').toString()) ?? 0;

                              // Si todos los filtros estÃ¡n vacÃ­os o raza es 'Todas', mostrar todas las ofertas
                              final mostrarTodas = (cantidadMin == 0) &&
                                  (razaFiltro == null ||
                                      razaFiltro == 'null' ||
                                      razaFiltro == '' ||
                                      razaFiltro == 'Todas') &&
                                  cpFiltro.isEmpty &&
                                  radioFiltro == 0;

                              final filteredDocs = mostrarTodas
                                  ? docs.where((doc) {
                                      final oferta = doc.data() as Map<String, dynamic>;
                                      return oferta['archivada'] != true;
                                    }).toList()
                                  : docs.where((doc) {
                                      final oferta = doc.data() as Map<String, dynamic>;
                                      if (oferta['archivada'] == true) return false;
                                      final cantidad =
                                          int.tryParse(oferta['cantidad']?.toString() ?? '') ?? 0;
                                      final raza = oferta['raza']?.toString() ?? '';

                                      if (cantidadMin > 0 && cantidad < cantidadMin) return false;
                                      if (razaFiltro != null &&
                                          razaFiltro != 'null' &&
                                          razaFiltro != '' &&
                                          razaFiltro != 'Todas' &&
                                          raza != razaFiltro) {
                                        return false;
                                      }

                                      // LÃ³gica de filtro CP y radio
                                      if (cpFiltro.isNotEmpty) {
                                        cpFiltro = cpFiltro.padLeft(5, '0');
                                        final ofertaCP = (oferta['cp']?.toString() ??
                                                oferta['codigoPostal']?.toString() ??
                                                '')
                                            .padLeft(5, '0');
                                        // Debug detallado opcional removido para reducir ruido
                                        if (radioFiltro > 0) {
                                          final coordsUser = cpCoords[cpFiltro];
                                          final coordsOferta = cpCoords[ofertaCP];
                                          // (coords debug omitidos)
                                          if (coordsUser == null || coordsOferta == null) {
                                            return false; // sin coordenadas vÃ¡lidas, descartada
                                          }
                                          final latUser = coordsUser[0];
                                          final lonUser = coordsUser[1];
                                          final latOferta = coordsOferta[0];
                                          final lonOferta = coordsOferta[1];
                                          final dist =
                                              haversine(latUser, lonUser, latOferta, lonOferta);
                                          if (dist <= radioFiltro) {
                                            return true;
                                          } else {
                                            return false;
                                          }
                                        } else {
                                          if (ofertaCP != cpFiltro) {
                                            return false;
                                          }
                                        }
                                      }
                                      return true;
                                    }).toList();
                              // logs eliminados para reducir ruido
                              if (filteredDocs.isEmpty) {
                                return const Text('No hay ofertas disponibles con esos filtros.',
                                    style: TextStyle(color: Colors.grey));
                              }
                              return ListView.builder(
                                itemCount: filteredDocs.length,
                                itemBuilder: (context, index) {
                                  final doc = filteredDocs[index];
                                  final oferta = doc.data() as Map<String, dynamic>;
                                  oferta['id'] = doc.id; // <-- AÃ±ade el ID del documento
                                  // Normalizar precio vacÃ­o a null para UI
                                  if ((oferta['precio'] is String &&
                                      oferta['precio'].toString().trim().isEmpty)) {
                                    oferta['precio'] = null;
                                  }
                                  final fotos = oferta['fotos'] as List<dynamic>?;
                                  final fotoPrincipal = fotos != null && fotos.isNotEmpty
                                      ? fotos[0].toString()
                                      : null;
                                  final precio = oferta['precio'] ?? '';
                                  final tipoPrecio =
                                      oferta['tipoPrecio']?.toString().replaceAll('eur_', 'â‚¬/') ??
                                          '';
                                  final cantidad = oferta['cantidad'] ?? '';
                                  final raza = oferta['raza'] ?? '';
                                  final enTrato = oferta['enTrato'] == true;
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 20),
                                    child: Stack(
                                      children: [
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute<Widget>(
                                                builder: (context) => DetalleOfertaScreen(
                                                  oferta: {
                                                    ...oferta,
                                                    'coleccion': 'vacas_ofertas',
                                                  },
                                                  fotos: fotos,
                                                ),
                                              ),
                                            );
                                          },
                                          child: Card(
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(16)),
                                            elevation: 4,
                                            child: Padding(
                                              padding: const EdgeInsets.all(12.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(12),
                                                    child: fotoPrincipal != null
                                                        ? Image.network(
                                                            fotoPrincipal,
                                                            width: 120,
                                                            height: 120,
                                                            fit: BoxFit.cover,
                                                          )
                                                        : Container(
                                                            width: 120,
                                                            height: 120,
                                                            color: Colors.grey[300],
                                                            child: const Center(
                                                              child: Text('Sin foto',
                                                                  style: TextStyle(
                                                                      color: Colors.grey)),
                                                            ),
                                                          ),
                                                  ),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text('$precio $tipoPrecio',
                                                            style: const TextStyle(
                                                                fontSize: 22,
                                                                fontWeight: FontWeight.bold,
                                                                color: Color(0xFF004d26))),
                                                        const SizedBox(height: 8),
                                                        Text('Cantidad: $cantidad',
                                                            style: const TextStyle(fontSize: 22)),
                                                        const SizedBox(height: 4),
                                                        Text('Raza: $raza',
                                                            style: const TextStyle(fontSize: 22)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (enTrato)
                                          Positioned(
                                            top: 0,
                                            left: 0,
                                            right: 0,
                                            child: Container(
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: Colors.red[700],
                                                borderRadius: const BorderRadius.only(
                                                  topLeft: Radius.circular(16),
                                                  topRight: Radius.circular(16),
                                                ),
                                              ),
                                              child: const Center(
                                                child: Text(
                                                  'Oferta en trato',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 18,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
// Importar la pantalla de detalle
