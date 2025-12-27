import 'package:flutter/material.dart';
import 'dart:async';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    const duration = Duration(milliseconds: 30);
    _timer = Timer.periodic(duration, (timer) {
      setState(() {
        _progress += 0.01;
        if (_progress >= 1.0) {
          timer.cancel();
          _navigateToHome();
        }
      });
    });
  }

  void _navigateToHome() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => widget.child),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo o texto SePagos
              const Text(
                'SePagos',
                style: TextStyle(
                  fontFamily: 'BebasNeue', // Usaremos una fuente similar a BBH Bartle
                  fontSize: 64,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2323),
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 60),
              
              // Barra de progreso
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.grey[300],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1F2323)),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
