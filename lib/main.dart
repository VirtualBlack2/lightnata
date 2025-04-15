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
import 'package:firebase_messaging/firebase_messaging.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    print('✅ Firebase initialized');

    await FirebaseMessaging.instance.requestPermission();
    print('✅ Notification permission granted');

    await FirebaseMessaging.instance.subscribeToTopic('announcements');
    print('✅ Subscribed to topic');

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedName = prefs.getString("username");
    print('✅ Username check complete: $savedName');

    runApp(MaterialApp(
      home: savedName != null ? LightnataApp(userName: savedName) : EntryScreen(),
      debugShowCheckedModeBanner: false,
    ));
  } catch (e, stacktrace) {
    print('❌ ERROR in main(): $e');
    print(stacktrace);
  }
}



class EntryScreen extends StatefulWidget {
  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  bool _showGreeting = false;

  late AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1000),
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
            Text("That's an awesome name,", style: TextStyle(fontSize: 20)),
            Text(
              _controller.text,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    transitionDuration: Duration(milliseconds: 600),
                    pageBuilder: (_, __, ___) => LightnataApp(userName: _controller.text),
                    transitionsBuilder: (_, animation, __, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                  ),
                );
              },
              child: Text("Continue"),
            ),
          ],
        )
            : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _bounceController,
              child: Text(
                "Hello!",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
            SizedBox(height: 20),
            Text("What should we call you?"),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(labelText: "Name"),
              ),
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

Set<Marker> _mapMarkers = {};


class LightnataApp extends StatefulWidget {
  final String userName;
  LightnataApp({required this.userName});

  @override
  State<LightnataApp> createState() => _LightnataAppState();
}

class _LightnataAppState extends State<LightnataApp> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  Set<Marker> _markers = {};
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

    // BYPASS daily limit for testing
    // SharedPreferences prefs = await SharedPreferences.getInstance();
    // String today = DateTime.now().toIso8601String().substring(0, 10);
    // String key = "$status-$today";

    // if (prefs.getBool(key) == true) {
    //   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("You’ve already reported $status today.")));
    //   return;
    // }

    bool confirm = await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Confirm Report"),
        content: Text(
          status == 'No Power'
              ? "You are reporting an outage. Please be sure you have no power. False reports don’t help the community."
              : status == 'Flickering'
              ? "You are reporting flickering lights or unstable power. Please confirm."
              : "You're reporting power has been restored. Please confirm.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("Confirm")),
        ],
      ),
    );

    if (!confirm) return;

    String area = await _getAreaFromLatLng(_currentLocation!.latitude, _currentLocation!.longitude);

    await FirebaseFirestore.instance.collection('outages').add({
      'lat': _currentLocation!.latitude,
      'lng': _currentLocation!.longitude,
      'status': status,
      'timestamp': Timestamp.now(),
      'area': area,
    });

    // await prefs.setBool(key, true); // Commented out for testing

    setState(() {
      _liveFeed.insert(0, "$area - $status at ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}");
      if (_liveFeed.length > 5) _liveFeed.removeLast();
    });
  }


  void _listenToReports() {
    FirebaseFirestore.instance.collection('outages').snapshots().listen((snapshot) async {
      Map<String, List<Map<String, dynamic>>> grouped = {};
      for (var doc in snapshot.docs) {
        var data = doc.data();
        var key = data['area'] ?? "${data['lat']},${data['lng']}";
        grouped.putIfAbsent(key, () => []).add(data);
      }

      Set<Marker> newMarkers = {};

      for (var entry in grouped.entries) {
        var reports = entry.value;
        if (reports.length < 1) continue;

        double avgLat = reports.map((r) => r['lat']).reduce((a, b) => a + b) / reports.length;
        double avgLng = reports.map((r) => r['lng']).reduce((a, b) => a + b) / reports.length;
        String latestStatus = reports.last['status'];

        String assetPath;
        if (latestStatus == 'No Power') assetPath = 'assets/out.png';
        else if (latestStatus == 'Flickering') assetPath = 'assets/flicker.png';
        else assetPath = 'assets/restore.png';

        final BitmapDescriptor icon = await BitmapDescriptor.fromAssetImage(
          ImageConfiguration(size: Size(48, 48)),
          assetPath,
        );

        newMarkers.add(Marker(
          markerId: MarkerId(entry.key),
          position: LatLng(avgLat, avgLng),
          icon: icon,
          infoWindow: InfoWindow(title: latestStatus),
        ));
      }

      setState(() {
        _mapMarkers = newMarkers;
      });
    });
  }



  void _listenToAnnouncements() {
    FirebaseFirestore.instance
        .collection('announcements')
        .doc('latest') // This always watches the latest published announcement
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        setState(() {
          announcementText = snapshot.data()!['text'] ?? "";
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
        title: Text('LightNata'),
        actions: [
          IconButton(
            icon: Icon(Icons.lock_open),
            onPressed: () {
              TextEditingController _adminPassController = TextEditingController();

              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text("Admin Access"),
                  content: TextField(
                    controller: _adminPassController,
                    obscureText: true,
                    decoration: InputDecoration(labelText: "Enter Admin Password"),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        if (_adminPassController.text == "123") {
                          Navigator.pop(context); // close dialog
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AdminLoginScreen()),
                          );
                        } else {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Wrong password")),
                          );
                        }
                      },
                      child: Text("Enter"),
                    ),
                  ],
                ),
              );
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
                  SlidingAnnouncement(text: announcementText),


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
    markers: _mapMarkers,
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
                      Row(
                        children: [
                          Image.asset('assets/out.png', height: 24),
                          SizedBox(width: 8),
                          Text(" No Power"),
                        ],
                      ),
                      Row(
                        children: [
                          Image.asset('assets/flicker.png', height: 24),
                          SizedBox(width: 8),
                          Text(" Flickering"),
                        ],
                      ),
                      Row(
                        children: [
                          Image.asset('assets/restore.png', height: 24),
                          SizedBox(width: 8),
                          Text(" Power Restored"),
                        ],
                      ),

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
    await FirebaseFirestore.instance
        .collection('announcements')
        .doc('latest') // always overwrite 'latest'
        .set({'text': msg});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Announcement published.")));
    _announcement.clear();
    setState(() {}); // force UI refresh
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
                onPressed: () {
                  final msg = _announcement.text.trim();
                  if (msg.isNotEmpty) {
                    _publishAnnouncement(msg);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text("Announcement can't be empty"),
                    ));
                  }
                },
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
//SLIDING ANIMATION FOR ANNOUNCEMENT
class SlidingAnnouncement extends StatefulWidget {
  final String text;
  const SlidingAnnouncement({required this.text});

  @override
  _SlidingAnnouncementState createState() => _SlidingAnnouncementState();
}

class _SlidingAnnouncementState extends State<SlidingAnnouncement>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _animation;
  bool isPaused = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: Duration(seconds: 30),
      vsync: this,
    );

    _animation = Tween<Offset>(
      begin: Offset(1.0, 0.0),
      end: Offset(-1.5, 0.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

    _startLoop();
  }

  void _startLoop() async {
    while (mounted) {
      setState(() => isPaused = false);
      await _controller.forward(from: 0.0);
      setState(() => isPaused = true);
      await Future.delayed(Duration(seconds: 60)); // stay static
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: Colors.green,
      padding: EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          // Fixed NAWEC logo filling the height
          Container(
            height: double.infinity,
            width: 40,
            child: Image.asset('assets/nawec.jpg', fit: BoxFit.cover),
          ),
          SizedBox(width: 10),

          // Sliding or Static text
          Expanded(
            child: isPaused
                ? Text(
              "📢 ${widget.text}",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            )
                : ClipRect(
              child: SlideTransition(
                position: _animation,
                child: Row(
                  children: [
                    Text(
                      "📢 ${widget.text}",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 30),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

