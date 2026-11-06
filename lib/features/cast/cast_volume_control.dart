import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Receiver volume, independent of the phone's speaker.
class CastVolumeControl extends StatefulWidget {
  const CastVolumeControl({super.key});

  @override
  State<CastVolumeControl> createState() => _CastVolumeControlState();
}

class _CastVolumeControlState extends State<CastVolumeControl> {
  static const _channel = MethodChannel('fr.twittervideo.client/cast_volume');

  double? _volume;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final volume = await _channel.invokeMethod<double>('getVolume');
      if (!mounted) return;
      setState(() {
        _volume = volume;
        _error = null;
      });
    } on PlatformException {
      if (!mounted) return;
      setState(() => _error = 'Volume du téléviseur indisponible.');
    }
  }

  Future<void> _setVolume(double value) async {
    setState(() {
      _volume = value;
      _error = null;
    });
    try {
      await _channel.invokeMethod<bool>('setVolume', {'volume': value});
    } on PlatformException {
      if (!mounted) return;
      setState(() => _error = 'Le Chromecast a refusé le réglage de volume.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_volume == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.volume_down_rounded),
            Expanded(
              child: Slider(
                value: _volume!.clamp(0.0, 1.0),
                onChanged: (value) => setState(() => _volume = value),
                // Avoid flooding remote Cast with drag events.
                onChangeEnd: _setVolume,
              ),
            ),
            const Icon(Icons.volume_up_rounded),
            SizedBox(
              width: 45,
              child: Text(
                ((_volume! * 100).round()).toString() + ' %',
                textAlign: TextAlign.right,
              ),
            ),
            IconButton(
              tooltip: 'Actualiser le volume de la TV',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _refresh,
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
      ],
    );
  }
}
