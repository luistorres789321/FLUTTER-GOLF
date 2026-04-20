import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const GeoDemoApp());
}

class GeoDemoApp extends StatelessWidget {
  const GeoDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Geolocator Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const GeoHomePage(),
    );
  }
}

class GeoHomePage extends StatefulWidget {
  const GeoHomePage({super.key, this.autoRefresh = true});

  final bool autoRefresh;

  @override
  State<GeoHomePage> createState() => _GeoHomePageState();
}

class _GeoHomePageState extends State<GeoHomePage> {
  LocationPermission? _permission;
  bool? _serviceEnabled;
  Position? _position;
  bool _loading = false;
  String _statusMessage = 'Pulsa "Comprobar estado" para empezar.';

  @override
  void initState() {
    super.initState();
    if (widget.autoRefresh) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    await _runSafely(() async {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();

      setState(() {
        _serviceEnabled = serviceEnabled;
        _permission = permission;
        _statusMessage = 'Estado actualizado.';
      });
    });
  }

  Future<void> _requestPermission() async {
    await _runSafely(() async {
      final permission = await Geolocator.requestPermission();
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();

      setState(() {
        _permission = permission;
        _serviceEnabled = serviceEnabled;
        _statusMessage = 'Permiso solicitado.';
      });
    });
  }

  Future<void> _getCurrentPosition() async {
    await _runSafely(() async {
      setState(() {
        _statusMessage = 'Obteniendo ubicacion...';
      });

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _serviceEnabled = false;
          _statusMessage = 'Los servicios de ubicacion estan desactivados.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _permission = permission;
          _statusMessage = 'Permiso denegado.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _permission = permission;
          _statusMessage =
              'Permiso denegado para siempre. Abre los ajustes de la app.';
        });
        return;
      }

      final position =
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              'No se pudo obtener la ubicacion en 10 segundos.',
            ),
          );

      setState(() {
        _permission = permission;
        _serviceEnabled = true;
        _position = position;
        _statusMessage = 'Ubicacion obtenida correctamente.';
      });
    });
  }

  Future<void> _openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  Future<void> _runSafely(Future<void> Function() action) async {
    setState(() {
      _loading = true;
    });

    try {
      await action();
    } on TimeoutException {
      setState(() {
        _statusMessage =
            'Tiempo de espera agotado. Revisa el permiso del navegador y la ubicacion del sistema.';
      });
    } catch (error) {
      setState(() {
        _statusMessage = 'Error: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _permissionLabel(LocationPermission? permission) {
    switch (permission) {
      case LocationPermission.always:
        return 'always';
      case LocationPermission.whileInUse:
        return 'whileInUse';
      case LocationPermission.denied:
        return 'denied';
      case LocationPermission.deniedForever:
        return 'deniedForever';
      case LocationPermission.unableToDetermine:
        return 'unableToDetermine';
      case null:
        return 'desconocido';
    }
  }

  String _serviceLabel(bool? enabled) {
    if (enabled == null) {
      return 'desconocido';
    }

    return enabled ? 'activados' : 'desactivados';
  }

  String _coordinateLabel(double? value) {
    if (value == null) {
      return '--';
    }

    return value.toStringAsFixed(6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Prueba Geolocator')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estado actual', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 16),
                      _InfoRow(
                        label: 'Permiso',
                        value: _permissionLabel(_permission),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Servicios',
                        value: _serviceLabel(_serviceEnabled),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Latitud',
                        value: _coordinateLabel(_position?.latitude),
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Longitud',
                        value: _coordinateLabel(_position?.longitude),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_statusMessage),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading ? null : _refreshStatus,
                icon: const Icon(Icons.refresh),
                label: const Text('Comprobar estado'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _requestPermission,
                icon: const Icon(Icons.verified_user),
                label: const Text('Pedir permiso'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _getCurrentPosition,
                icon: const Icon(Icons.my_location),
                label: const Text('Obtener ubicacion'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Abrir ajustes de la app'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading ? null : _openLocationSettings,
                icon: const Icon(Icons.location_searching),
                label: const Text('Abrir ajustes de ubicacion'),
              ),
              const SizedBox(height: 16),
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.bodyLarge),
      ],
    );
  }
}
