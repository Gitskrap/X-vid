import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});
  final Widget child;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate>
    with WidgetsBindingObserver {
  final LocalAuthentication _auth = LocalAuthentication();
  bool _unlocked = false;
  bool _authenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _authenticate();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // The biometric prompt itself may interrupt the app lifecycle.
      if (!_authenticating && _unlocked && mounted) {
        setState(() => _unlocked = false);
      }
    } else if (state == AppLifecycleState.resumed && !_unlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_authenticating && !_unlocked) _authenticate();
      });
    }
  }

  Future<void> _authenticate() async {
    if (!mounted || _authenticating || _unlocked) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final result = await _auth.authenticate(
        localizedReason: 'Déverrouiller Twitter vidéo',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!mounted) return;
      setState(() {
        _unlocked = result;
        if (!result) _error = 'Authentification annulée ou refusée.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Identification biométrique indisponible. '
              'Configure une empreinte ou un visage dans les paramètres '
              'de sécurité Android, puis réessaie.';
        });
      }
    } finally {
      if (mounted) setState(() => _authenticating = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_unlocked) return widget.child;
    return Scaffold(
      backgroundColor: const Color(0xFF070809),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF172522),
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    size: 58,
                    color: Color(0xFF70F0CE),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Twitter vidéo',
                  style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Identification biométrique requise',
                  style: TextStyle(color: Color(0xFFC6CFD3), fontSize: 15),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFFB4AB)),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _authenticating ? null : _authenticate,
                  icon: _authenticating
                      ? const SizedBox(
                          width: 19,
                          height: 19,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  label: Text(
                    _authenticating ? 'Vérification…' : 'Déverrouiller',
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'La vérification est réalisée par Android. '
                  'Aucune donnée biométrique n’est collectée par l’application.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA7AB), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
