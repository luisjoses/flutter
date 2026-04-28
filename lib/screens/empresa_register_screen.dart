import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/bysapp_app_bar_logo.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import 'persona_register_screen.dart' show TerminosCondicionesWidget;

class EmpresaRegisterScreen extends StatefulWidget {
  const EmpresaRegisterScreen({super.key});

  @override
  State<EmpresaRegisterScreen> createState() => _EmpresaRegisterScreenState();
}

class _EmpresaRegisterScreenState extends State<EmpresaRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _cifController = TextEditingController();
  final _emailController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _localidadController = TextEditingController();
  final _cpController = TextEditingController();
  final _direccionController = TextEditingController();
  final _passwordController = TextEditingController();
  final _password2Controller = TextEditingController();
  bool _aceptaTerminos = false;
  String? _error;
  String? _success;

  Future<void> _register() async {
    setState(() {
      _error = null;
      _success = null;
    });
    if (!_formKey.currentState!.validate()) return;
    final loc = AppLocalizations.of(context);
    if (!_aceptaTerminos) {
      setState(() => _error = loc.t('acceptTerms'));
      return;
    }
    if (_passwordController.text != _password2Controller.text) {
      setState(() => _error = loc.t('passwordsMismatch'));
      return;
    }
    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await FirebaseFirestore.instance.collection('usuarios').doc(userCredential.user!.uid).set({
        'nombre': _nombreController.text.trim(),
        'cif': _cifController.text.trim(),
        'email': _emailController.text.trim(),
        'telefono': _telefonoController.text.trim(),
        'localidad': _localidadController.text.trim(),
        'cp': _cpController.text.trim(),
        'direccion': _direccionController.text.trim(),
        'tipo': 'empresa',
      });
      setState(() => _success = AppLocalizations.of(context).t('registerSuccess'));
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushReplacementNamed(context, '/login');
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final bi = MyApp.of(context)?.bilingualMode ?? false;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const SizedBox.shrink(),
        flexibleSpace: const BysappAppBarLogo(),
        backgroundColor: const Color(0xFF004d26),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'bysapp',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Segoe Script',
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF003d1a),
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
                  Text(bi ? AppLocalizations.bilingual('registerTitle') : loc.t('registerTitle'),
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  _buildTextField(
                      _nombreController,
                      bi ? AppLocalizations.bilingual('businessName') : loc.t('businessName'),
                      true),
                  _buildTextField(_cifController,
                      bi ? AppLocalizations.bilingual('taxId') : loc.t('taxId'), true),
                  _buildTextField(_emailController,
                      bi ? AppLocalizations.bilingual('email') : loc.t('email'), true,
                      type: TextInputType.emailAddress),
                  _buildTextField(_telefonoController,
                      bi ? AppLocalizations.bilingual('phone') : loc.t('phone'), true,
                      type: TextInputType.phone),
                  _buildTextField(_localidadController,
                      bi ? AppLocalizations.bilingual('city') : loc.t('city'), true),
                  _buildTextField(_cpController,
                      bi ? AppLocalizations.bilingual('postalCode') : loc.t('postalCode'), true,
                      type: TextInputType.number),
                  _buildTextField(_direccionController,
                      bi ? AppLocalizations.bilingual('address') : loc.t('address'), true),
                  _buildTextField(_passwordController,
                      bi ? AppLocalizations.bilingual('password') : loc.t('password'), true,
                      isPassword: true, minLength: 6),
                  _buildTextField(
                      _password2Controller,
                      bi ? AppLocalizations.bilingual('confirmPassword') : loc.t('confirmPassword'),
                      true,
                      isPassword: true,
                      minLength: 6),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Checkbox(
                        value: _aceptaTerminos,
                        onChanged: (v) => setState(() {
                          _aceptaTerminos = v ?? false;
                        }),
                      ),
                      Expanded(
                        child: Wrap(
                          children: [
                            Text(bi
                                ? AppLocalizations.bilingual('acceptTerms')
                                : loc.t('acceptTerms')),
                            GestureDetector(
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(loc.t('termsAndConditions')),
                                    content: const SingleChildScrollView(
                                      child: TerminosCondicionesWidget(),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: Text(loc.t('close')),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Text(
                                  bi
                                      ? AppLocalizations.bilingual('termsAndConditions')
                                      : loc.t('termsAndConditions'),
                                  style: const TextStyle(
                                      color: Colors.blue, decoration: TextDecoration.underline)),
                            ),
                            const Text(' | '),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(context, '/privacy-policy'),
                              child: Text(
                                  bi
                                      ? AppLocalizations.bilingual('privacyPolicy')
                                      : loc.t('privacyPolicy'),
                                  style: const TextStyle(
                                      color: Colors.blue, decoration: TextDecoration.underline)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _register,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF004d26),
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                        bi ? AppLocalizations.bilingual('registerTitle') : loc.t('registerTitle'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  if (_success != null) ...[
                    const SizedBox(height: 8),
                    Text(_success!, style: const TextStyle(color: Colors.green)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, bool required,
      {TextInputType type = TextInputType.text, bool isPassword = false, int minLength = 0}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: SizedBox(
        height: 38,
        child: TextFormField(
          controller: controller,
          keyboardType: type,
          obscureText: isPassword,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: Colors.white,
          ),
          validator: (value) {
            final loc = AppLocalizations.of(context);
            if (required && (value == null || value.trim().isEmpty)) {
              return loc.t('requiredField');
            }
            if (minLength > 0 && (value == null || value.length < minLength)) {
              return loc.tf('minChars', {'min': minLength.toString()});
            }
            return null;
          },
        ),
      ),
    );
  }
}
