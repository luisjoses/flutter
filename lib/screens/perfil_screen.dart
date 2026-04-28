import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

class PerfilScreen extends StatelessWidget {
  const PerfilScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Perfil'),
          backgroundColor: const Color(0xFF004d26),
        ),
        body: const Center(child: Text('No has iniciado sesiÃ³n.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
        ),
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
        centerTitle: true,
        backgroundColor: const Color(0xFF004d26),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          // Logo suave de fondo
          Positioned.fill(
            child: Opacity(
              opacity: 0.08,
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('usuarios').doc(user.uid).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error al obtener datos: ${snapshot.error}'));
              }
              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Center(child: Text('No se encontraron datos de usuario.'));
              }
              final data = snapshot.data!.data() as Map<String, dynamic>;
              final telefonoController = TextEditingController(
                  text: data.containsKey('telefono') && data['telefono'] != null
                      ? data['telefono'].toString()
                      : '');
              final direccionController = TextEditingController(
                  text: data.containsKey('direccion') && data['direccion'] != null
                      ? data['direccion'].toString()
                      : '');
              bool isEditing = false;
              return StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              elevation: 2,
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Nombre: ${data['nombre'] ?? ''}',
                                        style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('apellidos'))
                                      Text('Apellidos: ${data['apellidos'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('dni'))
                                      Text('DNI/NIE: ${data['dni'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                    Text('Email: ${data['email'] ?? ''}',
                                        style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('localidad'))
                                      Text('Localidad: ${data['localidad'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('cp'))
                                      Text('CP: ${data['cp'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('cif'))
                                      Text('CIF: ${data['cif'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                    if (data.containsKey('tipo'))
                                      Text('Tipo: ${data['tipo'] ?? ''}',
                                          style: const TextStyle(fontSize: 18)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Card(
                              elevation: 2,
                              shape:
                                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('TelÃ©fono:',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextField(
                                      controller: telefonoController,
                                      enabled: isEditing,
                                      decoration: const InputDecoration(border: InputBorder.none),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('DirecciÃ³n:',
                                        style: TextStyle(fontWeight: FontWeight.bold)),
                                    TextField(
                                      controller: direccionController,
                                      enabled: isEditing,
                                      decoration: const InputDecoration(border: InputBorder.none),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (!isEditing)
                                          ElevatedButton(
                                            onPressed: () {
                                              setState(() {
                                                isEditing = true;
                                              });
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF004d26),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Editar',
                                                style: TextStyle(color: Colors.white)),
                                          ),
                                        if (isEditing)
                                          ElevatedButton(
                                            onPressed: () async {
                                              await FirebaseFirestore.instance
                                                  .collection('usuarios')
                                                  .doc(user.uid)
                                                  .update({
                                                'telefono': telefonoController.text.trim(),
                                                'direccion': direccionController.text.trim(),
                                              });
                                              setState(() {
                                                isEditing = false;
                                              });
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                    content:
                                                        Text('Datos actualizados correctamente')),
                                              );
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF004d26),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('Guardar',
                                                style: TextStyle(color: Colors.white)),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
