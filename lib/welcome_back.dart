import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // for LightnataApp import

class WelcomeBackScreen extends StatefulWidget {
  final String userName;
  const WelcomeBackScreen({required this.userName});

  @override
  _WelcomeBackScreenState createState() => _WelcomeBackScreenState();
}

class _WelcomeBackScreenState extends State<WelcomeBackScreen> {
  String _weather = '';
  bool _isDay = true;

  @override
  void initState() {
    super.initState();
    _fetchWeather().then((_) {
      // after showing the splash for 2s, navigate on:
      Future.delayed(Duration(seconds: 2), _goNext);
    });
  }

  Future<void> _fetchWeather() async {
    // call Open-Meteo
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
            '?latitude=YOUR_LAT&longitude=YOUR_LON'
            '&current_weather=true&temperature_unit=fahrenheit'
    );
    // if you need real coords, you can pass them via constructor or fetch Location here
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
  }

  void _goNext() {
    // once done, push the normal home
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LightnataApp(userName: widget.userName)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: _weather.isEmpty
            ? CircularProgressIndicator()
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Welcome back ${widget.userName}!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'The weather is $_weather ${_isDay ? "☀️" : "🌙"}',
              style: TextStyle(fontSize: 20),
            ),
          ],
        ),
      ),
    );
  }
}
