import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _showPassword = false;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _error;

  Future<void> _login() async {
    setState(() {
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // Persistencia del token FCM se gestiona en main.dart (_persistFcmToken)
      // para evitar duplicidad, tiempos de espera en web y uso de VAPID key.
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Widget _buildTextField(TextEditingController controller, String label, bool isPassword,
      {TextInputType type = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: SizedBox(
        height: 38,
        child: TextFormField(
          controller: controller,
          keyboardType: type,
          obscureText: isPassword ? !_showPassword : false,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(_showPassword ? Icons.visibility : Icons.visibility_off),
                    onPressed: () {
                      setState(() {
                        _showPassword = !_showPassword;
                      });
                    },
                  )
                : null,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final bool bi = MyApp.of(context)?.bilingualMode ?? false;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
        backgroundColor: const Color(0xFF004d26),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      DropdownButton<Locale>(
                        value: Localizations.localeOf(context),
                        underline: const SizedBox.shrink(),
                        items: supportedLocales.map((l) {
                          return DropdownMenuItem(
                            value: l,
                            child: Text(
                                l.languageCode == 'es' ? loc.t('spanish') : loc.t('portuguese')),
                          );
                        }).toList(),
                        onChanged: (locale) {
                          if (locale != null) {
                            MyApp.of(context)?.setLocale(locale);
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.t('appName'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily:
                          'Segoe Script', // Puedes cambiar por otra fuente si tienes una personalizada
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF003d1a), // Verde mÃ¡s oscuro
                      letterSpacing: 2,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(bi ? AppLocalizations.bilingual('loginTitle') : loc.t('loginTitle'),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  _buildTextField(_emailController,
                      bi ? AppLocalizations.bilingual('email') : loc.t('email'), false,
                      type: TextInputType.emailAddress),
                  _buildTextField(_passwordController,
                      bi ? AppLocalizations.bilingual('password') : loc.t('password'), true),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        if (_emailController.text.isEmpty) {
                          setState(() {
                            _error = loc.t('enterEmailToReset');
                          });
                          return;
                        }
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(
                            email: _emailController.text.trim(),
                          );
                          setState(() {
                            _error = loc.t('resetEmailSent');
                          });
                        } catch (e) {
                          setState(() {
                            _error = loc.t('resetEmailError');
                          });
                        }
                      },
                      child: Text(loc.t('forgotPassword'),
                          style: const TextStyle(
                              color: Color(0xFF004d26), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ...existing code...
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 2 / 3,
                        child: ElevatedButton(
                          onPressed: _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004d26),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(bi ? AppLocalizations.bilingual('enter') : loc.t('enter'),
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width * 2 / 3,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pushNamed(context, '/register');
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004d26),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: Text(
                              bi
                                  ? AppLocalizations.bilingual('createAccount')
                                  : loc.t('createAccount'),
                              style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      loc.t('welcomeCommunity'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF004d26),
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
