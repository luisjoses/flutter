import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'screens/chat_contraoferta_screen.dart';
import 'screens/comprar_cabras_screen.dart';
import 'screens/comprar_cerdos_screen.dart';
import 'screens/comprar_otros_screen.dart';
import 'screens/comprar_ovejas_screen.dart';
import 'screens/comprar_screen.dart';
import 'screens/comprar_vacas_screen.dart';
import 'screens/empresa_register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/mis_ofertas_screen.dart';
import 'screens/perfil_screen.dart';
import 'screens/persona_register_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/register_screen.dart';
import 'screens/vender_cabras_screen_fixed.dart';
import 'screens/vender_cerdos_screen.dart';
import 'screens/vender_otros_screen.dart';
import 'screens/vender_ovejas_screen.dart';
import 'screens/vender_screen.dart';
import 'screens/vender_vacas_screen.dart';

bool _skipFcm = false; // controlado por ?nofcm
bool _skipAppCheck = false; // controlado por ?noappcheck
String? _webVapidKey; // opcional en web (?vapid=...)

void main() async {
  // Captura errores Dart que de otro modo quedan silenciosos en web release
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('FLUTTER_ERROR: ${details.exception}\n${details.stack}');
    FlutterError.presentError(details);
  };

  runZonedGuarded(() async {
    await _bootstrap();
  }, (Object error, StackTrace stack) {
    debugPrint('DART_ZONE_ERROR: $error\n$stack');
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  } else {
    // En móvil usamos configuración nativa (google-services / GoogleService-Info.plist).
    await Firebase.initializeApp();
  }
  // Detectar parámetros en web para aislar problemas (Edge): ?nofcm & ?noappcheck
  if (kIsWeb) {
    final params = Uri.base.queryParameters;
    _skipFcm = params.containsKey('nofcm');
    _skipAppCheck = params.containsKey('noappcheck');
    const vapidFromEnv = String.fromEnvironment('FCM_WEB_VAPID_KEY');
    _webVapidKey = params['vapid'] ?? (vapidFromEnv.isNotEmpty ? vapidFromEnv : null);
    if (_skipFcm) debugPrint('FCM desactivado por ?nofcm');
    if (_skipAppCheck) debugPrint('AppCheck desactivado por ?noappcheck');
  }

  // App Check (omitible si ?noappcheck)
  if (!_skipAppCheck) {
    try {
      if (kIsWeb) {
        // Solo activar si se ha configurado una clave real; evita bloqueos en Edge con claves dummy.
        const siteKey = String.fromEnvironment('RECAPTCHA_V3_SITE_KEY');
        if (siteKey.isNotEmpty) {
          await FirebaseAppCheck.instance.activate(
            webProvider: ReCaptchaV3Provider(siteKey),
          );
        } else {
          debugPrint('AppCheck en web omitido (sin clave RECAPTCHA_V3_SITE_KEY)');
        }
      } else {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
          appleProvider: AppleProvider.appAttest,
        );
      }
    } catch (e) {
      debugPrint('AppCheck init error: $e');
    }
  }

  // Configuración de FCM (omitible si ?nofcm)
  if (!_skipFcm) {
    try {
      // Difiriendo hasta después del primer frame para evitar bloqueos de arranque en Edge
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final messaging = FirebaseMessaging.instance;
          await messaging.requestPermission();
          FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        } catch (e) {
          debugPrint('FCM post-frame init error: $e');
        }
      });
    } catch (e) {
      debugPrint('FCM init error: $e');
    }
  }
  runApp(const MyApp());
}

// Handler global para mensajes en background (Android/iOS)
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Asegura inicialización si el isolate se despertó
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } else {
      await Firebase.initializeApp();
    }
  } catch (_) {}
  // Aquí podrías registrar logs o actualizar estado local (limitado en background)
  debugPrint('Background message id=${message.messageId}');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) => context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('es');
  bool _bilingualMode = false;
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  String? _pendingChatId;
  bool _fcmInitialized = false;
  bool _openingChat = false;

  Future<void> _refreshAndPersistFcmToken() async {
    final messaging = FirebaseMessaging.instance;
    try {
      if (!kIsWeb) {
        final token = await messaging.getToken();
        await _persistFcmToken(token);
        return;
      }
      final vapid = _webVapidKey;
      if (vapid != null && vapid.isNotEmpty) {
        final token = await messaging.getToken(vapidKey: vapid);
        await _persistFcmToken(token);
      }
    } catch (e) {
      debugPrint('FCM token refresh error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLocale();
    // Registrar listeners FCM sólo si no se desactivó por parámetro
    if (!_skipFcm) {
      _setupFcmListeners();
    }
  }

  Future<void> _loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('app_locale');
      if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
        setState(() {
          _locale = Locale(code);
        });
      }
      // Modo bilingue retirado de UI: mantenemos idioma unico y limpiamos preferencia legacy.
      await prefs.setBool('bilingual_mode', false);
      if (_bilingualMode) {
        setState(() => _bilingualMode = false);
      }
    } catch (_) {}
  }

  void setLocale(Locale locale) {
    if (_locale.languageCode == locale.languageCode) return;
    setState(() => _locale = locale);
    _persistLocale(locale.languageCode);
  }

  void toggleBilingual(bool value) {
    if (_bilingualMode) {
      setState(() => _bilingualMode = false);
    }
    _persistBilingual(false);
  }

  bool get bilingualMode => _bilingualMode;

  Future<void> _persistLocale(String code) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_locale', code);
    } catch (_) {}
  }

  Future<void> _persistBilingual(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('bilingual_mode', value);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'bysapp',
      navigatorKey: _navKey,
      locale: _locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthGate(),
      routes: {
        '/login': (context) => const _AuthGate(),
        '/register': (context) => const RegisterScreen(),
        '/persona-register': (context) => const PersonaRegisterScreen(),
        '/empresa-register': (context) => const EmpresaRegisterScreen(),
        '/home': (context) => const _AuthGate(),
        '/comprar': (context) => const ComprarScreen(),
        '/vender': (context) => const VenderScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/perfil': (context) => const PerfilScreen(),
        '/comprar-vacas': (context) => const ComprarVacasScreen(),
        '/comprar-ovejas': (context) => const ComprarOvejasScreen(),
        '/comprar-cabras': (context) => const ComprarCabrasScreen(),
        '/comprar-cerdos': (context) => const ComprarCerdosScreen(),
        '/comprar-otros': (context) => const ComprarOtrosScreen(),
        '/vender-vacas': (context) => const VenderVacasScreen(),
        '/vender-ovejas': (context) => const VenderOvejasScreen(),
        '/vender-cabras': (context) => const VenderCabrasScreen(),
        '/vender-cerdos': (context) => const VenderCerdosScreen(),
        '/vender-otros': (context) => const VenderOtrosScreen(),
        '/mis-ofertas': (context) => const MisOfertasScreen(),
      },
    );
  }

  // Intenta abrir un chat si hay uno pendiente y usuario autenticado
  void _tryOpenPendingChat() {
    final chatId = _pendingChatId;
    if (chatId == null) return;
    if (FirebaseAuth.instance.currentUser == null) return; // esperar login
    _navigateToChat(chatId);
  }

  void _setupFcmListeners() {
    if (_fcmInitialized) return; // evitar múltiples registros en hot reload
    _fcmInitialized = true;
    final messaging = FirebaseMessaging.instance;
    // Cuando la app está en foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground: ${message.messageId}');
      _showForegroundNotificationSnack(message);
    });
    // Token refresh
    messaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM token refrescado: $newToken');
      _persistFcmToken(newToken);
    });
    // Token inicial
    if (!kIsWeb) {
      messaging.getToken().then(_persistFcmToken).catchError((Object e) {
        debugPrint('FCM getToken error: $e');
      });
    } else {
      final vapid = _webVapidKey;
      if (vapid != null && vapid.isNotEmpty) {
        messaging.getToken(vapidKey: vapid).then(_persistFcmToken).catchError((Object e) {
          debugPrint('FCM web getToken error: $e');
        });
      } else {
        debugPrint('Skipping messaging.getToken on web (sin FCM_WEB_VAPID_KEY)');
      }
    }

    // Mensaje que abrió la app desde terminada
    messaging.getInitialMessage().then((message) {
      if (message != null) {
        final chatId = message.data['chatId'];
        if (chatId != null && chatId.toString().isNotEmpty) {
          _pendingChatId = chatId.toString();
          _tryOpenPendingChat();
        }
      }
    });

    // App en background -> user toca notificación
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final chatId = message.data['chatId'];
      if (chatId != null && chatId.toString().isNotEmpty) {
        _navigateToChat(chatId.toString());
      }
    });

    // Escuchar cambios de autenticación para abrir chat pendiente tras login
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _refreshAndPersistFcmToken();
        _tryOpenPendingChat();
      }
    });
  }

  Future<void> _persistFcmToken(String? token) async {
    if (token == null) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // solo guardar si hay sesión
      await FirebaseFirestore.instance.collection('usuarios').doc(user.uid).set(
        {'fcmToken': token, 'fcmTokenUpdatedAt': DateTime.now().toIso8601String()},
        SetOptions(merge: true),
      );
      debugPrint('FCM token guardado/actualizado en Firestore');
    } catch (e) {
      debugPrint('Error guardando FCM token: $e');
    }
  }

  void _showForegroundNotificationSnack(RemoteMessage message) {
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    final chatId = message.data['chatId'];
    if (chatId == null) return; // si no es de chat, ignorar aquí
    final loc = AppLocalizations.of(ctx);
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(loc.t('newProposalArrived')),
        action: SnackBarAction(
          label: loc.t('view'),
          onPressed: () => _navigateToChat(chatId.toString()),
          textColor: Colors.yellowAccent,
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _navigateToChat(String chatId) async {
    if (_openingChat) return; // evitar doble apertura
    _openingChat = true;
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        _pendingChatId = chatId;
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('chats').doc(chatId).get();
      if (!doc.exists) {
        debugPrint('Chat $chatId no encontrado');
        return;
      }
      final data = doc.data() ?? {};
      if (!mounted) return; // asegurar que el State sigue vivo tras await
      final ctx = _navKey.currentContext;
      if (ctx == null) return;
      Navigator.of(ctx).push(MaterialPageRoute<Widget>(
        builder: (_) => ChatContraofertaScreen(
          chatId: chatId,
          ofertaId: (data['ofertaId'] ?? chatId).toString(),
          coleccion: (data['coleccion'] ?? 'vacas_ofertas').toString(),
          vendedorId: (data['vendedorId'] ?? '').toString(),
          tipoPrecio: (data['tipoPrecio'] ?? '').toString(),
          formaPago: (data['formaPago'] ?? '').toString(),
          fechaSalida: (data['fecha'] ?? '').toString(),
          precioInicial: double.tryParse((data['precio'] ?? '0').toString()) ?? 0,
          raza: (data['raza'] ?? '').toString(),
          cantidad: (data['cantidad'] ?? '').toString(),
        ),
      ));
      // Limpiar unreadFor para este usuario
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('chats').doc(chatId).update({
          'unreadFor': FieldValue.arrayRemove([uid])
        });
      }
      _pendingChatId = null;
    } catch (e) {
      debugPrint('Error navegando a chat: $e');
    } finally {
      _openingChat = false;
    }
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  late final Future<User?> _restoreFuture;

  @override
  void initState() {
    super.initState();
    _restoreFuture = _waitForAuthRestore();
  }

  Future<User?> _waitForAuthRestore() async {
    final deadline = DateTime.now().add(const Duration(seconds: 4));
    User? user = FirebaseAuth.instance.currentUser;
    while (user == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      user = FirebaseAuth.instance.currentUser;
    }
    return user;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<User?>(
      future: _restoreFuture,
      builder: (context, restoreSnapshot) {
        if (restoreSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.idTokenChanges(),
          initialData: restoreSnapshot.data ?? FirebaseAuth.instance.currentUser,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            if (snapshot.data != null) {
              return const HomeScreen();
            }

            return const LoginScreen();
          },
        );
      },
    );
  }
}
