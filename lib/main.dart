// pubspec.yaml dependencies:
// firebase_core: ^2.32.0
// cloud_firestore: ^5.6.6
// shared_preferences: ^2.2.2
// google_maps_flutter: ^2.5.0
// geolocator: ^10.1.0
// geocoding: ^2.2.0
// marquee: ^2.2.3

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:marquee/marquee.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedName = prefs.getString("username");

  runApp(MaterialApp(
    home: savedName != null ? LightnataApp(userName: savedName) : EntryScreen(),
    debugShowCheckedModeBanner: false,
  ));
}

class EntryScreen extends StatefulWidget {
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _showGreeting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _showGreeting
            ? Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("That's an awesome name,", style: TextStyle(fontSize: 20)),
            Text(_controller.text, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                await prefs.setString("username", _controller.text);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LightnataApp(userName: _controller.text)));
              },
              child: Text("Continue"),
            )
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedDefaultTextStyle(
              duration: Duration(milliseconds: 500),
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
              child: Text("Hello!"),
            ),
            SizedBox(height: 20),
            Text("What should we call you?"),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(controller: _controller, decoration: InputDecoration(labelText: "Name")),
            ),
            ElevatedButton(
              onPressed: () => setState(() => _showGreeting = true),
              child: Text("Submit"),
            )
          ],
        ),
      ),
    );
  }
}

class LightnataApp extends StatefulWidget {
  final String userName;
  LightnataApp({required this.userName});

  @override
  State<LightnataApp> createState() => _LightnataAppState();
}

class _LightnataAppState extends State<LightnataApp> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  Map<CircleId, Circle> _circles = {};
  List<String> _liveFeed = [];
  String announcementText = "";

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _listenToReports();
    _listenToAnnouncements();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;
    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  Future<String> _getAreaFromLatLng(double lat, double lng) async {
    List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isNotEmpty) {
      Placemark place = placemarks[0];
      return place.locality ?? place.subAdministrativeArea ?? "Unknown Area";
    }
    return "Unknown Area";
  }

  Future<void> _submitReport(String status) async {
    if (_currentLocation == null) return;
    String area = await _getAreaFromLatLng(_currentLocation!.latitude, _currentLocation!.longitude);

    await FirebaseFirestore.instance.collection('outages').add({
      'lat': _currentLocation!.latitude,
      'lng': _currentLocation!.longitude,
      'status': status,
      'timestamp': Timestamp.now(),
      'area': area,
    });

    setState(() {
      _liveFeed.insert(0, "$area - $status at ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}");
      if (_liveFeed.length > 5) _liveFeed.removeLast();
    });
  }
  void _listenToReports() {
    FirebaseFirestore.instance.collection('outages').snapshots().listen((snapshot) {
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var doc in snapshot.docs) {
        var data = doc.data();
        var key = data['area'] ?? "${data['lat']},${data['lng']}";
        grouped.putIfAbsent(key, () => []).add(data);
      }

      Map<CircleId, Circle> newCircles = {};
      grouped.forEach((key, reports) {
        if (reports.length < 10) return;

        double avgLat = reports.map((r) => r['lat']).reduce((a, b) => a + b) / reports.length;
        double avgLng = reports.map((r) => r['lng']).reduce((a, b) => a + b) / reports.length;
        String latestStatus = reports.last['status'];

        Color color;
        if (latestStatus == 'No Power') color = Colors.red;
        else if (latestStatus == 'Flickering') color = Colors.yellow;
        else color = Colors.green;

        final circle = Circle(
          circleId: CircleId(key),
          center: LatLng(avgLat, avgLng),
          radius: 100 + (reports.length * 8),
          fillColor: color.withOpacity(0.4),
          strokeWidth: 2,
          strokeColor: color.withOpacity(0.8),
        );

        newCircles[circle.circleId] = circle;
      });

      setState(() {
        _circles = newCircles;
      });
    });
  }

  void _listenToAnnouncements() {
    FirebaseFirestore.instance.collection('announcements').snapshots().listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        setState(() {
          announcementText = snapshot.docs.last.data()['text'] ?? "";
        });
      }
    });
  }

  String _greeting() {
    int hour = DateTime.now().hour;
    if (hour < 12) return "Good Morning";
    if (hour < 17) return "Good Afternoon";
    return "Good Evening";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Lightnata'),
        actions: [
          IconButton(
            icon: Icon(Icons.lock_open),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLoginScreen()));
            },
          )
        ],
      ),
      body: _currentLocation == null
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
          child: Column(
              children: [
              SizedBox(height: 10),
          Text("${_greeting()}, ${widget.userName}", style: TextStyle(fontSize: 20)),
          SizedBox(height: 10),
          if (announcementText.isNotEmpty)
      Container(
      height: 30,
      color: Colors.green,
      child: Marquee(
        text: "📢 $announcementText",
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        velocity: 30.0,
      ),
    ),
    Padding(
    padding: const EdgeInsets.all(12.0),
    child: Text("Is your power out?", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    ),
    SizedBox(
    height: 400,
    child: GoogleMap(
    onMapCreated: (controller) => _mapController = controller,
    initialCameraPosition: CameraPosition(target: _currentLocation!, zoom: 14),
    myLocationEnabled: true,
    circles: Set.from(_circles.values),
    ),
    ),
                Wrap(
                  spacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: () => _submitReport('No Power'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: Text('Report Outage', style: TextStyle(color: Colors.black)),
                    ),
                    ElevatedButton(
                      onPressed: () => _submitReport('Flickering'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow),
                      child: Text('Flickering', style: TextStyle(color: Colors.black)),
                    ),
                    ElevatedButton(
                      onPressed: () => _submitReport('Power Restored'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                      child: Text('Power Restored', style: TextStyle(color: Colors.black)),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Live Feed:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ..._liveFeed.map((e) => Text("• $e")),
                      SizedBox(height: 15),
                      Text("Legend:", style: TextStyle(fontWeight: FontWeight.bold)),
                      Row(children: [Icon(Icons.circle, color: Colors.red), Text(" No Power")]),
                      Row(children: [Icon(Icons.circle, color: Colors.yellow), Text(" Flickering")]),
                      Row(children: [Icon(Icons.circle, color: Colors.green), Text(" Power Restored")]),
                    ],
                  ),
                ),
              ],
          ),
      ),
    );
  }
}

class AdminLoginScreen extends StatefulWidget {
  @override
  _AdminLoginScreenState createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController _user = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  final TextEditingController _announcement = TextEditingController();
  bool isLoggedIn = false;
  String dropdownValue = "Select Area";
  List<String> areaOptions = [];

  @override
  void initState() {
    super.initState();
    _fetchAreaOptions();
  }

  void _fetchAreaOptions() async {
    var snapshot = await FirebaseFirestore.instance.collection('outages').get();
    Set<String> areas = {};
    for (var doc in snapshot.docs) {
      var data = doc.data();
      if (data.containsKey('area')) areas.add(data['area']);
    }
    setState(() {
      areaOptions = areas.toList();
    });
  }

  void _clearArea(String area) async {
    var snapshot = await FirebaseFirestore.instance.collection('outages').where('area', isEqualTo: area).get();
    for (var doc in snapshot.docs) {
      await doc.reference.delete();
    }

    await FirebaseFirestore.instance.collection('outages').add({
      'lat': 0,
      'lng': 0,
      'status': 'Power Restored',
      'timestamp': Timestamp.now(),
      'area': area,
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Area '$area' marked as restored.")));
  }

  void _publishAnnouncement(String msg) async {
    if (msg.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('announcements').add({'text': msg});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Announcement published.")));
    _announcement.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text("NAWEC Admin Panel", style: TextStyle(color: Colors.black)),
        centerTitle: true,
      ),
      body: Center(
        child: isLoggedIn
            ? SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              Image.asset('assets/nawec.jpg', height: 100),
              SizedBox(height: 20),
              Text("Welcome Admin", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              SizedBox(height: 15),
              DropdownButton<String>(
                value: dropdownValue,
                onChanged: (value) => setState(() => dropdownValue = value!),
                items: areaOptions.map((area) => DropdownMenuItem(value: area, child: Text(area))).toList()
                  ..insert(0, DropdownMenuItem(value: "Select Area", child: Text("Select Area"))),
              ),
              ElevatedButton(
                onPressed: () {
                  if (dropdownValue != "Select Area") _clearArea(dropdownValue);
                },
                child: Text("Report Power Restored"),
              ),
              SizedBox(height: 20),
              TextField(
                controller: _announcement,
                decoration: InputDecoration(labelText: "Enter announcement"),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _publishAnnouncement(_announcement.text),
                child: Text("Publish"),
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => setState(() => isLoggedIn = false),
                child: Text("Logout"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
              )
            ],
          ),
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/nawec.jpg', height: 100),
            SizedBox(height: 20),
            Text("ADMIN LOGIN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(controller: _user, decoration: InputDecoration(labelText: "Username")),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(controller: _pass, decoration: InputDecoration(labelText: "Password"), obscureText: true),
            ),
            ElevatedButton(
              onPressed: () {
                if (_user.text == "Admin" && _pass.text == "123") {
                  setState(() => isLoggedIn = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Invalid credentials")));
                }
              },
              child: Text("Login"),
            )
          ],
        ),
      ),
    );
  }
}

