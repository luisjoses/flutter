import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

class ComprarScreen extends StatelessWidget {
  const ComprarScreen({super.key});

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
              padding: const EdgeInsets.all(24.0),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 32),
                    const Text('Â¿QuÃ© quieres comprar?',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 32),
                    _buildAnimalButton(context, 'Ovejas'),
                    const SizedBox(height: 16),
                    _buildAnimalButton(context, 'Cabras'),
                    const SizedBox(height: 16),
                    _buildAnimalButton(context, 'Vacas'),
                    const SizedBox(height: 16),
                    _buildAnimalButton(context, 'Cerdos'),
                    const SizedBox(height: 16),
                    _buildAnimalButton(context, 'Otros'),
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

Widget _buildAnimalButton(BuildContext context, String animal) {
  return Container(
    width: 260,
    height: 100,
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
            if (animal == 'Vacas') {
              Navigator.pushNamed(context, '/comprar-vacas');
            } else if (animal == 'Ovejas') {
              Navigator.pushNamed(context, '/comprar-ovejas');
            } else if (animal == 'Cabras') {
              Navigator.pushNamed(context, '/comprar-cabras');
            } else if (animal == 'Cerdos') {
              Navigator.pushNamed(context, '/comprar-cerdos');
            } else if (animal == 'Otros') {
              Navigator.pushNamed(context, '/comprar-otros');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF004d26),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
          child: Text(animal, style: const TextStyle(fontSize: 22, color: Colors.white)),
        ),
      ),
    ),
  );
}
