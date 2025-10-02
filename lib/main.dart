import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';

// global state
ValueNotifier<int> reportIntensity = ValueNotifier<int>(5);
ValueNotifier<double> glowRadius = ValueNotifier<double>(120);
ValueNotifier<bool> heatmapMode = ValueNotifier<bool>(false);

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  _cameras = await availableCameras();
  runApp(const LightPollutionApp());
}

class LightPollutionApp extends StatelessWidget {
  const LightPollutionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Light Pollution App',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

// -------------------- SPLASH SCREEN --------------------
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              "Light Pollution",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const MainAppScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text("Proceed"),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- MAIN APP WITH TABS --------------------
class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    MapScreen(),
    ArScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: "Map"),
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: "AR"),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: "Settings"),
        ],
      ),
    );
  }
}

// -------------------- MAP SCREEN --------------------
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final FirestoreService _firestore = FirestoreService();
  final List<Marker> _markers = [];

  Color _getMarkerColor(int intensity) {
    if (intensity <= 3) return Colors.green;
    if (intensity <= 7) return Colors.orange;
    return Colors.red;
  }

  double _getMarkerSize(int intensity) {
    if (intensity <= 3) return 20;
    if (intensity <= 7) return 30;
    return 40;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.getReports(),
        builder: (context, snapshot) {
          _markers.clear();

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              final lat = doc['lat'] as double;
              final lng = doc['lng'] as double;
              final intensity = doc['intensity'] as int;

              _markers.add(
                Marker(
                  point: LatLng(lat, lng),
                  width: _getMarkerSize(intensity),
                  height: _getMarkerSize(intensity),
                  child: Icon(
                    Icons.brightness_1,
                    color: _getMarkerColor(intensity),
                    size: _getMarkerSize(intensity),
                  ),
                ),
              );
            }
          }

          return FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(37.7749, -122.4194),
              initialZoom: 3,
              onTap: (tapPosition, latlng) async {
                await _firestore.addReport(
                  latlng.latitude,
                  latlng.longitude,
                  reportIntensity.value, // use chosen intensity
                );
              },
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.example.light_pollution',
              ),
              MarkerLayer(markers: _markers),
            ],
          );
        },
      ),
    );
  }
}

// -------------------- AR SCREEN --------------------
class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  CameraController? _controller;
  final List<Offset> _lightSources = [];
  final FirestoreService _firestore = FirestoreService();

  @override
  void initState() {
    super.initState();
    _controller = CameraController(_cameras.first, ResolutionPreset.medium);
    _controller!.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _reportLight() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission denied")),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);

    await _firestore.addReport(
      position.latitude,
      position.longitude,
      reportIntensity.value,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Light report submitted!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: GestureDetector(
        onTapDown: (details) {
          setState(() {
            _lightSources.add(details.localPosition);
          });
        },
        child: Stack(
          children: [
            CameraPreview(_controller!),
            ValueListenableBuilder<double>(
              valueListenable: glowRadius,
              builder: (context, radius, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: heatmapMode,
                  builder: (context, heatmap, _) {
                    return CustomPaint(
                      painter:
                          LightOverlayPainter(_lightSources, radius, heatmap),
                      child: Container(),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _reportLight,
        label: const Text("Report Light"),
        icon: const Icon(Icons.add_location_alt),
        backgroundColor: Colors.orange,
      ),
    );
  }
}

class LightOverlayPainter extends CustomPainter {
  final List<Offset> lightSources;
  final double radius;
  final bool heatmap;

  LightOverlayPainter(this.lightSources, this.radius, this.heatmap);

  Color _getColorForIntensity(int intensity) {
    if (intensity <= 3) return Colors.green;
    if (intensity <= 7) return Colors.orange;
    return Colors.red;
  }

  double _getOpacityForIntensity(int intensity) {
    if (intensity <= 3) return 0.3;
    if (intensity <= 7) return 0.5;
    return 0.7;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = reportIntensity.value;
    final baseColor = _getColorForIntensity(intensity);
    final opacity = _getOpacityForIntensity(intensity);

    for (var source in lightSources) {
      final paint = Paint();

      if (heatmap) {
        paint.color = baseColor.withOpacity(opacity);
      } else {
        paint.shader = RadialGradient(
          colors: [
            baseColor.withOpacity(opacity),
            Colors.transparent,
          ],
        ).createShader(
          Rect.fromCircle(center: source, radius: radius),
        );
      }

      canvas.drawCircle(source, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant LightOverlayPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.lightSources != lightSources ||
        oldDelegate.heatmap != heatmap ||
        reportIntensity.value != reportIntensity.value;
  }
}


// -------------------- SETTINGS SCREEN --------------------
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Adjust Light Spread", style: TextStyle(fontSize: 18)),
            ValueListenableBuilder<double>(
              valueListenable: glowRadius,
              builder: (context, value, _) {
                return Slider(
                  value: value,
                  min: 50,
                  max: 250,
                  divisions: 10,
                  label: value.round().toString(),
                  onChanged: (newValue) {
                    glowRadius.value = newValue;
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            const Text("Report Intensity", style: TextStyle(fontSize: 18)),
            ValueListenableBuilder<int>(
              valueListenable: reportIntensity,
              builder: (context, value, _) {
                return Slider(
                  value: value.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: value.toString(),
                  onChanged: (newValue) {
                    reportIntensity.value = newValue.toInt();
                  },
                );
              },
            ),
            const SizedBox(height: 20),
            ValueListenableBuilder<bool>(
              valueListenable: heatmapMode,
              builder: (context, value, _) {
                return SwitchListTile(
                  title: const Text("Enable Heatmap Mode"),
                  value: value,
                  onChanged: (val) {
                    heatmapMode.value = val;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
