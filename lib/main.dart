// ──────────────────────────────────────────────────────────────────────────────
// pubspec.yaml dependencies:
// firebase_core: ^2.32.0
// cloud_firestore: ^5.6.6
// shared_preferences: ^2.2.2
// google_maps_flutter: ^2.5.0
// geolocator: ^10.1.0
// geocoding: ^2.2.0
// marquee: ^2.2.3
// ──────────────────────────────────────────────────────────────────────────────

// ──────────────────────────────────────────────────────────────────────────────
// Imports
// ──────────────────────────────────────────────────────────────────────────────
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'dart:convert';

// ──────────────────────────────────────────────────────────────────────────────
// Application Entry
// ──────────────────────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await FirebaseMessaging.instance.requestPermission();
  await FirebaseMessaging.instance.subscribeToTopic('announcements');
  final prefs = await SharedPreferences.getInstance();
  final savedName = prefs.getString('username');
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: savedName == null
        ? const EntryScreen()
        : WelcomeBackScreen(userName: savedName),
  ));
}

// ──────────────────────────────────────────────────────────────────────────────
// AnimatedPulseCircle Model
// ──────────────────────────────────────────────────────────────────────────────
class AnimatedCircle {
  final LatLng position;
  final Color color;
  late AnimationController controller;
  late Animation<double> radius;

  AnimatedCircle({
    required this.position,
    required TickerProvider vsync,
    required this.color,
  }) {
    controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: vsync,
    )..repeat(reverse: true);

    radius = Tween<double>(begin: 100, end: 200).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );
  }

  void dispose() => controller.dispose();
}

// ──────────────────────────────────────────────────────────────────────────────
// EntryScreen (new users)
// ──────────────────────────────────────────────────────────────────────────────
class EntryScreen extends StatefulWidget {
  const EntryScreen({Key? key}) : super(key: key);
  @override
  _EntryScreenState createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _showGreeting = false;
  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
      lowerBound: 0.9,
      upperBound: 1.1,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _showGreeting
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("That's an awesome name,", style: TextStyle(fontSize: 20)),
            Text(
              _controller.text,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('username', _controller.text);
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    transitionDuration: const Duration(milliseconds: 600),
                    pageBuilder: (_, __, ___) =>
                        WelcomeBackScreen(userName: _controller.text),
                    transitionsBuilder: (_, animation, __, child) =>
                        FadeTransition(opacity: animation, child: child),
                  ),
                );
              },
              child: const Text("Continue"),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _bounceController,
              child: const Text(
                "Hello!",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
            const SizedBox(height: 20),
            const Text("What should we call you?"),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(labelText: "Name"),
              ),
            ),
            ElevatedButton(
              onPressed: () => setState(() => _showGreeting = true),
              child: const Text("Submit"),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Welcome‐back Splash Screen
// ──────────────────────────────────────────────────────────────────────────────
class WelcomeBackScreen extends StatefulWidget {
  final String userName;
  const WelcomeBackScreen({Key? key, required this.userName}) : super(key: key);

  @override
  _WelcomeBackScreenState createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen> {
  String _weather = '';
  bool _isDay = true;
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _determinePosition().then((_) => _fetchWeather());
  }

  Future<void> _determinePosition() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return;
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(pos.latitude, pos.longitude);
    });
  }

  Future<void> _fetchWeather() async {
    if (_currentLocation == null) return;
    final lat = _currentLocation!.latitude;
    final lon = _currentLocation!.longitude;
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon'
          '&current_weather=true&temperature_unit=fahrenheit',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      final t = (data['current_weather']['temperature'] as num).round();
      final h = DateTime.now().hour;
      setState(() {
        _weather = '$t°F';
        _isDay = h >= 6 && h < 18;
      });
    }
    // after 2s splash, go to main app
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LightnataApp(userName: widget.userName),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _weather.isEmpty
            ? const CircularProgressIndicator()
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome back ${widget.userName}!',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'The weather is $_weather ${_isDay ? '☀️' : '🌙'}',
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// LightnataApp (main dashboard)
// ──────────────────────────────────────────────────────────────────────────────
class LightnataApp extends StatefulWidget {
  final String userName;
  const LightnataApp({Key? key, required this.userName}) : super(key: key);

  @override
  _LightnataAppState createState() => _LightnataAppState();
}

Set<Marker> _mapMarkers = {};

class _LightnataAppState extends State<LightnataApp> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  List<String> _liveFeed = [];
  String announcementText = "";
  List<AnimatedCircle> _animatedCircles = [];
  String _weather = '';
  bool _isDaytime = true;

  @override
  void initState() {
    super.initState();
    _listenToAnnouncements();
    FirebaseMessaging.onMessage.listen((msg) {
      final b = msg.notification?.body;
      if (b != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(b)));
    });

    _determinePosition().then((_) {
      if (_currentLocation != null) {
        final test = AnimatedCircle(position: _currentLocation!, vsync: this, color: Colors.blue);
        test.controller.addListener(() => setState(() {}));
        _animatedCircles.add(test);
      }
      _listenToReports();
      _fetchWeather();
    });
  }

  @override
  void dispose() {
    for (var ac in _animatedCircles) ac.dispose();
    super.dispose();
  }

  Future<void> _fetchWeather() async {
    if (_currentLocation == null) return;
    final lat = _currentLocation!.latitude, lon = _currentLocation!.longitude;
    final url = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
          '?latitude=$lat&longitude=$lon'
          '&current_weather=true&temperature_unit=fahrenheit',
    );
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = json.decode(res.body);
      final t = (data['current_weather']['temperature'] as num).round();
      final h = DateTime.now().hour;
      setState(() {
        _weather = '$t°F';
        _isDaytime = h >= 6 && h < 18;
      });
    }
  }

  Future<void> _determinePosition() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) return;
    final pos = await Geolocator.getCurrentPosition();
    setState(() => _currentLocation = LatLng(pos.latitude, pos.longitude));
  }

  Future<String> _getAreaFromLatLng(double lat, double lng) async {
    final places = await placemarkFromCoordinates(lat, lng);
    if (places.isNotEmpty) {
      final p = places.first;
      return p.locality ?? p.subAdministrativeArea ?? "Unknown Area";
    }
    return "Unknown Area";
  }

  void _listenToAnnouncements() {
    FirebaseFirestore.instance
        .collection('announcements')
        .doc('latest')
        .snapshots()
        .listen((snap) {
      if (snap.exists) setState(() => announcementText = snap.data()?['text'] ?? "");
    });
  }

  void _listenToReports() {
    FirebaseFirestore.instance.collection('outages').snapshots().listen((snap) {
      final now = DateTime.now(), cutoff = now.subtract(const Duration(minutes: 5));
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (var d in snap.docs) {
        final m = d.data(), ts = (m['timestamp'] as Timestamp?)?.toDate();
        if (ts == null || ts.isBefore(cutoff)) continue;
        final lat = (m['lat'] as num).toDouble(), lng = (m['lng'] as num).toDouble();
        final k = "${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}";
        grouped.putIfAbsent(k, () => []).add(m);
      }
      _mapMarkers.clear();
      for (var ac in _animatedCircles) ac.dispose();
      _animatedCircles.clear();

      grouped.forEach((k, reps) {
        reps.sort((a, b) =>
            (a['timestamp'] as Timestamp).toDate().compareTo((b['timestamp'] as Timestamp).toDate()));
        final avgLat = reps.map((r) => (r['lat'] as num).toDouble()).reduce((a, b) => a + b) / reps.length;
        final avgLng = reps.map((r) => (r['lng'] as num).toDouble()).reduce((a, b) => a + b) / reps.length;
        final center = LatLng(avgLat, avgLng);
        final status = reps.last['status'] as String;
        final color = status == 'No Power'
            ? Colors.red
            : status == 'Flickering'
            ? Colors.yellow
            : Colors.green;

        _mapMarkers.add(Marker(markerId: MarkerId(k), position: center, infoWindow: InfoWindow(title: status)));
        final ac = AnimatedCircle(position: center, vsync: this, color: color);
        ac.controller.addListener(() => setState(() {}));
        _animatedCircles.add(ac);
      });

      setState(() {});
    });
  }

  Future<void> _submitReport(String status) async {
    if (_currentLocation == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Confirm Report"),
        content: Text("Confirm $status?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes")),
        ],
      ),
    );
    if (ok != true) return;

    final area = await _getAreaFromLatLng(_currentLocation!.latitude, _currentLocation!.longitude);
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final key = '$area-$today';
    if (prefs.getBool(key) == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You’ve already reported today in $area.")));
      return;
    }
    await prefs.setBool(key, true);

    await FirebaseFirestore.instance.collection('outages').add({
      'lat': _currentLocation!.latitude,
      'lng': _currentLocation!.longitude,
      'status': status,
      'timestamp': Timestamp.now(),
      'area': area,
    });

    setState(() {
      _liveFeed.insert(0, "$area - $status at ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2,'0')}");
      if (_liveFeed.length > 5) _liveFeed.removeLast();
    });
  }

  Future<BitmapDescriptor> _createMarkerBitmap(Color bg, String txt) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    final paint = Paint()..color = bg;
    const sz = 100.0;
    canvas.drawCircle(Offset(sz/2, sz/2), sz/2, paint);
    final tp = TextPainter(text: TextSpan(text: txt, style: const TextStyle(color: Colors.white, fontSize: 28)), textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, Offset((sz-tp.width)/2, (sz-tp.height)/2));
    final img = await rec.endRecording().toImage(sz.toInt(), sz.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bd!.buffer.asUint8List());
  }

  Set<Circle> _buildRippleCircles() {
    return _animatedCircles.map((anim) {
      final r = anim.radius.value;
      final fade = ((1 - (r - 100) / 100) * 0.5).clamp(0.0, 0.5);
      return Circle(circleId: CircleId(anim.position.toString()), center: anim.position, radius: r, fillColor: anim.color.withOpacity(fade), strokeWidth: 0);
    }).toSet();
  }

  void _openAdminDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Admin Access"),
        content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: "Enter Admin Password")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (ctrl.text == "123") {
                Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLoginScreen()));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong password")));
              }
            },
            child: const Text("Enter"),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return "Good Morning";
    if (h < 17) return "Good Afternoon";
    return "Good Evening";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('LightNata'),
        actions: [IconButton(icon: const Icon(Icons.lock_open), onPressed: _openAdminDialog)],
      ),
      body: _currentLocation == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Text("${_greeting()}, ${widget.userName}", style: const TextStyle(fontSize: 20)),
            if (announcementText.isNotEmpty) SlidingAnnouncement(text: announcementText),
            if (_weather.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('$_weather ${_isDaytime ? "☀️" : "🌙"}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            const Padding(padding: EdgeInsets.all(12.0), child: Text("Is your power out?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            SizedBox(
              height: 400,
              child: GoogleMap(
                onMapCreated: (c) => _mapController = c,
                initialCameraPosition: CameraPosition(target: _currentLocation!, zoom: 14),
                myLocationEnabled: true,
                markers: _mapMarkers,
                circles: _buildRippleCircles(),
              ),
            ),
            Wrap(
              spacing: 10,
              children: [
                ElevatedButton(onPressed: () => _submitReport('No Power'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Report Outage', style: TextStyle(color: Colors.black))),
                ElevatedButton(onPressed: () => _submitReport('Flickering'), style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow), child: const Text('Flickering', style: TextStyle(color: Colors.black))),
                ElevatedButton(onPressed: () => _submitReport('Power Restored'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Power Restored', style: TextStyle(color: Colors.black))),
              ],
            ),
            if (_liveFeed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text("Live Feed:", style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._liveFeed.map((e) => Text("• $e")),
                  const SizedBox(height: 16),
                  const Text("Statuses:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(children: [Image.asset('assets/redcircle.png', width: 24, height: 24), const SizedBox(width: 8), const Text("Power Outage")]),
                  const SizedBox(height: 4),
                  Row(children: [Image.asset('assets/yellowcircle.png', width: 24, height: 24), const SizedBox(width: 8), const Text("Unstable Power")]),
                  const SizedBox(height: 4),
                  Row(children: [Image.asset('assets/greencircle.png', width: 24, height: 24), const SizedBox(width: 8), const Text("Power Restored")]),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Admin Panel
// ──────────────────────────────────────────────────────────────────────────────
class AdminLoginScreen extends StatefulWidget {
  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _user = TextEditingController(), _pass = TextEditingController(), _announcement = TextEditingController();
  bool isLoggedIn = false;
  String dropdownValue = "Select Area";
  List<String> areaOptions = [];

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance.collection('outages').get().then((snap) {
      setState(() {
        areaOptions = snap.docs.map((d) => d.data()['area'] as String).toSet().toList();
      });
    });
  }

  void _clearArea(String area) async {
    final snap = await FirebaseFirestore.instance.collection('outages').where('area', isEqualTo: area).get();
    for (var d in snap.docs) await d.reference.delete();
    await FirebaseFirestore.instance.collection('outages').add({'lat': 0, 'lng': 0, 'status': 'Power Restored', 'timestamp': Timestamp.now(), 'area': area});
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('$area-${DateTime.now().toIso8601String().split('T')[0]}');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Area '$area' marked restored.")));
  }

  void _publishAnnouncement(String msg) async {
    if (msg.isEmpty) return;
    await FirebaseFirestore.instance.collection('announcements').doc('latest').set({'text': msg});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement published.")));
    _announcement.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("NAWEC Admin Panel", style: TextStyle(color: Colors.black)), backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context))),
      body: Center(
        child: isLoggedIn
            ? SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Image.asset('assets/nawec.jpg', height: 100),
              const SizedBox(height: 20),
              const Text("Welcome Admin", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: dropdownValue,
                items: ["Select Area", ...areaOptions].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                onChanged: (v) => setState(() => dropdownValue = v!),
              ),
              ElevatedButton(onPressed: dropdownValue != "Select Area" ? () => _clearArea(dropdownValue) : null, child: const Text("Report Restored")),
              TextField(controller: _announcement, decoration: const InputDecoration(labelText: "Enter announcement")),
              ElevatedButton(onPressed: () => _publishAnnouncement(_announcement.text.trim()), child: const Text("Publish")),
              ElevatedButton(onPressed: () => setState(() => isLoggedIn = false), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey), child: const Text("Logout")),
            ],
          ),
        )
            : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Image.asset('assets/nawec.jpg', height: 100),
          const Text("ADMIN LOGIN", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          TextField(controller: _user, decoration: const InputDecoration(labelText: "Username")),
          TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
          ElevatedButton(
              onPressed: () {
                if (_user.text == "Admin" && _pass.text == "123") {
                  setState(() => isLoggedIn = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid credentials")));
                }
              },
              child: const Text("Login")),
        ]),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// SlidingAnnouncement Widget
// ──────────────────────────────────────────────────────────────────────────────
class SlidingAnnouncement extends StatefulWidget {
  final String text;
  const SlidingAnnouncement({Key? key, required this.text}) : super(key: key);
  @override
  _SlidingAnnouncementState createState() => _SlidingAnnouncementState();
}

class _SlidingAnnouncementState extends State<SlidingAnnouncement> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  bool isPaused = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(seconds: 30), vsync: this);
    _animation = Tween<Offset>(begin: const Offset(1, 0), end: const Offset(-1.5, 0))
        .animate(CurvedAnimation(parent: _controller, curve: Curves.linear));
    _startLoop();
  }

  void _startLoop() async {
    while (mounted) {
      setState(() => isPaused = false);
      await _controller.forward(from: 0.0);
      setState(() => isPaused = true);
      await Future.delayed(const Duration(seconds: 60));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.green,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Image.asset('assets/nawec.jpg', height: 40),
          const SizedBox(width: 10),
          Expanded(
            child: isPaused
                ? Text('📢 ${widget.text}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.fade, softWrap: false)
                : SlideTransition(position: _animation, child: Text('📢 ${widget.text}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.fade, softWrap: false)),
          ),
        ],
      ),
    );
  }
}
