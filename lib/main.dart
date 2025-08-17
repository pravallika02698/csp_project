import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_sms/flutter_sms.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(const EmergencyApp());
}

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Emergency App',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const LoginScreen(),
    );
  }
}

// ------------------- LOGIN SCREEN -------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _childContactsController = TextEditingController();

  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', _nameController.text);
    await prefs.setStringList('children', _childContactsController.text.split(',')); // comma-separated
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => const EmergencyDashboard()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login / Register')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Your Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _childContactsController,
            decoration: const InputDecoration(
                labelText: 'Children Contacts (comma-separated)'),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saveUserData,
            child: const Text('Save & Continue'),
          ),
        ]),
      ),
    );
  }
}

// ------------------- EMERGENCY DASHBOARD -------------------
class EmergencyDashboard extends StatefulWidget {
  const EmergencyDashboard({super.key});

  @override
  State<EmergencyDashboard> createState() => _EmergencyDashboardState();
}

class _EmergencyDashboardState extends State<EmergencyDashboard> {
  late stt.SpeechToText _speech;
  late FlutterTts _tts;
  bool _isListening = false;
  String _command = '';
  List<String> childrenContacts = [];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _tts = FlutterTts();
    _loadChildrenContacts();
  }

  Future<void> _loadChildrenContacts() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      childrenContacts = prefs.getStringList('children') ?? [];
    });
  }

  Future<Position?> _determinePosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _tts.speak('Location services are disabled.');
      return null;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        await _tts.speak('Location permission denied.');
        return null;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await _tts.speak('Location permissions are permanently denied.');
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: const Duration(seconds: 10),
    );
  }

  void _startListening() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() => _isListening = true);
      _speech.listen(onResult: (val) {
        setState(() {
          _command = val.recognizedWords.toLowerCase();
        });
        if (_command.contains('help') || _command.contains('emergency')) {
          _triggerEmergency();
        }
      });
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  Future<void> _triggerEmergency() async {
    await _tts.speak('Emergency detected. Calling ambulance and notifying children.');

    // Call ambulance
    const ambulanceNumber = 'tel:102'; // Change if needed
    if (await canLaunchUrl(Uri.parse(ambulanceNumber))) {
      await launchUrl(Uri.parse(ambulanceNumber));
    }

    // Send SMS to children
    Position? pos = await _determinePosition();
    String message =
        'Emergency alert! Your parent needs help at location: https://www.google.com/maps/search/?api=1&query=${pos?.latitude},${pos?.longitude}';

    if (childrenContacts.isNotEmpty) {
      await sendSMS(message: message, recipients: childrenContacts)
          .catchError((e) => print('SMS Error: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency Dashboard')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(children: [
          Text(
            'Command: $_command',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _isListening ? _stopListening : _startListening,
            child: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _triggerEmergency,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Trigger Emergency Manually'),
          ),
        ]),
      ),
    );
  }
}
