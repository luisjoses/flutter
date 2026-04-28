import 'package:flutter/material.dart';

class BysappAppBarLogo extends StatelessWidget {
  const BysappAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        bottom: false,
        child: Center(
          child: SizedBox(
            height: 40,
            child: Image.asset(
              'assets/images/logo.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ),
    );
  }
}
