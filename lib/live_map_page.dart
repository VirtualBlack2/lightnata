import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ──────────────────────────────────────────────────────────────────────────────
// AnimatedCircle: encapsulates a pulsing animation for a map circle
// ──────────────────────────────────────────────────────────────────────────────
class AnimatedCircle {
  final LatLng position;
  final Color color;
  late final AnimationController controller;
  late final Animation<double> radius;

  AnimatedCircle({
    required this.position,
    required TickerProvider vsync,
    required this.color,
  }) {
    controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: vsync,
    )..repeat(reverse: true);

    radius = Tween<double>(
      begin: 100,
      end: 200,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
  }

  void dispose() => controller.dispose();
}

// ──────────────────────────────────────────────────────────────────────────────
// LiveMapPage: displays a Google Map with pulsing outage reports
// ──────────────────────────────────────────────────────────────────────────────
class LiveMapPage extends StatefulWidget {
  @override
  _LiveMapPageState createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage>
    with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;

  /// Holds one AnimatedCircle per outage cluster
  List<AnimatedCircle> _animatedCircles = [];

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _listenToReports();
  }

  @override
  void dispose() {
    for (final ac in _animatedCircles) {
      ac.dispose();
    }
    super.dispose();
  }

  /// Retrieves the user's current position
  Future<void> _determinePosition() async {
    final permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
    });
  }

  /// Listens to Firestore 'outages' and creates pulsing circles per cluster
  void _listenToReports() {
    FirebaseFirestore.instance.collection('outages').snapshots().listen((
      snapshot,
    ) async {
      // 1) Filter and group recent docs by rounded location
      final now = DateTime.now();
      final cutoff = now.subtract(Duration(minutes: 5));
      final grouped = <String, List<Map<String, dynamic>>>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['timestamp'] as Timestamp?;
        // skip stale or malformed
        if (ts == null || ts.toDate().isBefore(cutoff)) continue;
        final lat = data['lat'] as num?;
        final lng = data['lng'] as num?;
        if (lat == null || lng == null) continue;

        final key =
            "${lat.toDouble().toStringAsFixed(3)},${lng.toDouble().toStringAsFixed(3)}";
        grouped.putIfAbsent(key, () => []).add(data);
      }

      // 2) Tear down old animations
      for (var ac in _animatedCircles) ac.dispose();
      _animatedCircles.clear();

      // 3) Build new AnimatedCircles
      for (var entry in grouped.entries) {
        final reps = entry.value;
        final avgLat =
            reps
                .map((r) => (r['lat'] as num).toDouble())
                .reduce((a, b) => a + b) /
            reps.length;
        final avgLng =
            reps
                .map((r) => (r['lng'] as num).toDouble())
                .reduce((a, b) => a + b) /
            reps.length;
        final center = LatLng(avgLat, avgLng);
        final status = reps.last['status'] as String;

        // skip "Power Restored" clusters
        if (status == 'Power Restored') continue;

        final color =
            status == 'No Power'
                ? Colors.red
                : status == 'Flickering'
                ? Colors.yellow
                : Colors.green;

        // create and start pulsing
        final ac = AnimatedCircle(position: center, vsync: this, color: color);
        ac.controller.addListener(() => setState(() {}));
        _animatedCircles.add(ac);
      }

      // force redraw
      setState(() {});
    });
  }

  /// Converts AnimatedCircles into Google Map Circle objects
  Set<Circle> _buildRippleCircles() {
    return _animatedCircles.map((anim) {
      final r = anim.radius.value; // radius animates 100→200→100
      // fade: r=100→opacity=0.5, r=200→opacity=0.0
      final fade = ((1 - (r - 100) / 100) * 0.5).clamp(0.0, 0.5);

      return Circle(
        circleId: CircleId(anim.position.toString()),
        center: anim.position,
        radius: r,
        fillColor: anim.color.withOpacity(fade),
        strokeColor: anim.color.withOpacity(fade * 2),
        strokeWidth: 2,
      );
    }).toSet();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentLocation == null) {
      return Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: (controller) => _mapController = controller,
          initialCameraPosition: CameraPosition(
            target: _currentLocation!,
            zoom: 13,
          ),
          myLocationEnabled: true,
          circles: _buildRippleCircles(),
        ),
        Positioned(
          bottom: 20,
          left: 20,
          child: Container(
            padding: EdgeInsets.all(10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.circle, color: Colors.red),
                    SizedBox(width: 4),
                    Text("No Power"),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.circle, color: Colors.yellow),
                    SizedBox(width: 4),
                    Text("Flickering"),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.circle, color: Colors.green),
                    SizedBox(width: 4),
                    Text("Power Restored"),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
