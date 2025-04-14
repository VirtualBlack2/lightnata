import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LiveMapPage extends StatefulWidget {
  @override
  _LiveMapPageState createState() => _LiveMapPageState();
}

class _LiveMapPageState extends State<LiveMapPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  Map<CircleId, Circle> _circles = {};

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _listenToReports();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return;

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  void _listenToReports() {
    FirebaseFirestore.instance.collection('outages').snapshots().listen((snapshot) {
      Map<String, int> grouped = {};
      Map<String, String> statuses = {};
      Map<String, LatLng> groupedLatLng = {};

      for (var doc in snapshot.docs) {
        var data = doc.data();
        double roundedLat = double.parse((data['lat']).toStringAsFixed(3));
        double roundedLng = double.parse((data['lng']).toStringAsFixed(3));
        var key = "$roundedLat,$roundedLng";

        grouped[key] = (grouped[key] ?? 0) + 1;
        statuses[key] = data['status'];
        groupedLatLng[key] = LatLng(roundedLat, roundedLng);
      }

      Map<CircleId, Circle> newCircles = {};
      grouped.forEach((key, count) {
        LatLng center = groupedLatLng[key]!;
        String status = statuses[key]!;

        Color color;
        if (status == 'No Power') color = Colors.red;
        else if (status == 'Flickering') color = Colors.yellow;
        else color = Colors.green;

        double radius = 100 + (count * 15); // bigger for impact

        final circle = Circle(
          circleId: CircleId(key),
          center: center,
          radius: radius.toDouble(),
          fillColor: color.withOpacity(0.5),
          strokeWidth: 0,
        );
        newCircles[circle.circleId] = circle;
      });

      setState(() {
        _circles = newCircles;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return _currentLocation == null
        ? Center(child: CircularProgressIndicator())
        : Stack(
      children: [
        GoogleMap(
          onMapCreated: (controller) => _mapController = controller,
          initialCameraPosition: CameraPosition(
            target: _currentLocation!,
            zoom: 13,
          ),
          myLocationEnabled: true,
          circles: Set.from(_circles.values),
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
                Row(children: [Icon(Icons.circle, color: Colors.red), SizedBox(width: 4), Text("No Power")]),
                Row(children: [Icon(Icons.circle, color: Colors.yellow), SizedBox(width: 4), Text("Flickering")]),
                Row(children: [Icon(Icons.circle, color: Colors.green), SizedBox(width: 4), Text("Power Restored")]),
              ],
            ),
          ),
        )
      ],
    );
  }
}
