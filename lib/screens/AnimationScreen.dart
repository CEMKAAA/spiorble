import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spiroble/bluetooth/bluetooth_constant.dart';
import 'package:spiroble/bluetooth/BluetoothConnectionManager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:collection';

class AnimationScreen extends StatefulWidget {
  @override
  _AnimationScreenState createState() => _AnimationScreenState();
}

class Measurement {
  final double flowRate;
  final double volume;
  final double time;

  Measurement({
    required this.flowRate,
    required this.volume,
    required this.time,
  });
}

class MetricsPushKeyProvider with ChangeNotifier {
  String? _metricsPushKey;

  String? get metricsPushKey => _metricsPushKey;

  void setMetricsPushKey(String? key) {
    _metricsPushKey = key;
    notifyListeners();
  }
}

class _AnimationScreenState extends State<AnimationScreen>
    with SingleTickerProviderStateMixin {
  late BluetoothConnectionManager _bleManager;
  StreamSubscription<List<double>>? _dataSubscription;

  DiscoveredDevice? deviceToConnect;

  // Measurement data
  Queue<Measurement> measurements = Queue<Measurement>();
  Queue<Measurement> measurementsToStore = Queue<Measurement>();
  Queue<Measurement> buffer = Queue<Measurement>();

  bool isAnimating = false;
  bool isGravityActive = false;
  double gravityDecrement = 0.04;
  Timer? gravityTimer;
  Timer? _bufferTimer;

  double fvc = 0.0;
  double fev1 = 0.0;
  double pef = 0.0;
  double fev6 = 0.0;
  double fev2575 = 0.0;
  double fev1Fvc = 0.0;

  late AnimationController _controller;
  late Animation<double> _ballAnimation;
  int _timerCount = 10;
  late Timer? _timer;

  @override
  void initState() {
    super.initState();
    _bleManager =
        Provider.of<BluetoothConnectionManager>(context, listen: false);

    _controller = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 500),
        lowerBound: 0.0,
        upperBound: 1.0);

    _ballAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _controller.dispose(); // Dispose AnimationController if initialized
    _timer?.cancel(); // Cancel Timer if initialized
    gravityTimer?.cancel();
    _bufferTimer?.cancel();
    super.dispose();
  }

  // Save metricsPushKey to SharedPreferences
  Future<void> saveMetricsPushKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('metricsPushKey', key);
  }

  Future<void> addDummyData() async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      print('User is not logged in!!');
      return;
    }

    String userId = user.uid;

    final DatabaseReference databaseRef =
        FirebaseDatabase.instance.ref("sonuclar/$userId/tests");

    String testId = databaseRef.push().key!;

    double fvc = 3.5;
    double fev1 = 2.8;
    double pef = 6.0;
    double fev6 = 3.2;
    double fef2575 = 4.5;
    double fev1Fvc = 80.0;

    List<Map<String, dynamic>> measurementsDummy = [];

    for (int i = 0; i < 100; i++) {
      measurementsDummy.add({
        "flowRate":
            (3.0 + Random().nextDouble()), // Random value between 3.0 and 4.0
        "volume":
            (1.0 + Random().nextDouble()), // Random value between 1.0 and 2.0
        "time": (i),
      });
    }

    Map<String, dynamic> metricsData = {
      'timestamp': DateTime.now().toIso8601String(),
      'fvc': fvc,
      'fev1': fev1,
      'pef': pef,
      'fev6': fev6,
      'fef2575': fef2575,
      'fev1Fvc': fev1Fvc,
      'measurements': measurementsDummy,
    };

    try {
      await databaseRef.child(testId).set(metricsData);
      print('Dummy data successfully saved!');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dummy data added successfully!')),
      );
    } catch (e) {
      print('Error saving dummy data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding dummy data: $e')),
      );
    }
  }

  // Load metricsPushKey from SharedPreferences
  Future<String?> loadMetricsPushKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('metricsPushKey');
  }

  void _startAnimation() async {
    if (_bleManager.connectedDeviceId != null) {
      await _bleManager.sendChar1(
        BleUuids.Uuid3Services,
        BleUuids.Uuid3Characteristic,
        _bleManager.connectedDeviceId!,
      );

      setState(() {
        isAnimating = true;
        _timerCount = 10;
      });

      _bufferTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
        if (!isAnimating) {
          timer.cancel();
          return;
        }

        if (buffer.isNotEmpty) {
          // Calculate average values from the buffer
          double avgFlowRate =
              buffer.map((m) => m.flowRate).reduce((a, b) => a + b) /
                  buffer.length;
          double avgVolume =
              buffer.map((m) => m.volume).reduce((a, b) => a + b) /
                  buffer.length;
          double avgTime =
              buffer.map((m) => m.time).reduce((a, b) => a + b) / buffer.length;

          setState(() {
            measurementsToStore.addLast(
              Measurement(
                flowRate: avgFlowRate,
                volume: avgVolume,
                time: avgTime,
              ),
            );

            if (measurementsToStore.length > 100) {
              measurementsToStore.removeFirst();
            }
          });

          buffer.clear();
        }
      });

      // Listen to incoming data streams
      _dataSubscription =
          _bleManager.notifyAsDoubles(_bleManager.connectedDeviceId!).listen(
        (data) {
          print(
              'Received Data - flowRate: ${data[0]}, Volume: ${data[1]}, Time: ${data[2]}');
          final newMeasurement = Measurement(
            flowRate: data[0],
            volume: data[1],
            time: data[2],
          );

          setState(() {
            measurements.addLast(newMeasurement);
            buffer.addLast(newMeasurement);

            if (measurements.length > 10000) {
              measurements.removeFirst();
            }

            if (buffer.length > 10000) {
              buffer.removeFirst();
            }

            _calculateMetrics();
          });
          // Optionally, you can call _calculateMetrics() here if needed
          // However, since metrics are calculated in the Timer, it's not necessary
        },
        onError: (error) {
          print('Error receiving data $error');
        },
      );

      _startTimer();
    } else {
      print('No device connected');
    }
  }

  void _stopAnimation() {
    _dataSubscription?.cancel();
    _bleManager.stopScan();

    setState(() {
      isAnimating = false;
    });

    _timer?.cancel();
    gravityTimer?.cancel();
    _bufferTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bağlantı iptal edildi')),
    );
  }

  String getMeasurementKey(int index) {
    return 'measurement_${index.toString().padLeft(5, '0')}';
  }

  void _startTimer() async {
    _timer = Timer.periodic(Duration(seconds: 1), (timer) async {
      if (_timerCount == 0) {
        _timer?.cancel();
        gravityTimer?.cancel();
        _bufferTimer?.cancel();
        _controller.stop();
        //_bleManager.connectToDevice(deviceToConnect!.id);

        // Sıkıştırılmış measurement datasını kullanalım :)
        List<Map<String, dynamic>> serializedMeasurements = measurementsToStore
            .map((m) => {
                  'flowRate': m.flowRate,
                  'volume': m.volume,
                  'time': m.time,
                })
            .toList();

        User? user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          print('Kullanıcı giriş yapmamış!');
          return;
        }
        String userId = user.uid;
        print('User ID: $userId');

        final databaseRef = FirebaseDatabase.instance.ref();

        try {
          print('Attempting to generate a push key for metrics...');
          String testId =
              databaseRef.child('sonuclar/$userId/tests').push().key!;

          Map<String, dynamic> metricsData = {
            'timestamp': DateTime.now().toIso8601String(),
            'fvc': fvc,
            'fev1': fev1,
            'pef': pef,
            'fev6': fev6,
            'fef2575': fev2575,
            'fev1Fvc': fev1Fvc,
            'measurements': serializedMeasurements
          };

          // Set the metrics data
          await databaseRef
              .child('sonuclar/$userId/tests/$testId')
              .set(metricsData);

          print('Sonuç başarıyla kaydedildi!');
        } catch (e) {
          print('Sonuç kaydedilirken bir hata oluştu: $e');
        }
      } else {
        if (!mounted) return;
        setState(() {
          _timerCount--;
        });
      }
    });
  }

  void _calculateMetrics() {
    if (measurements.isEmpty) return;

    // Extract flow rates, volumes, and times from measurements
    List<double> akisHizi = measurements.map((m) => m.flowRate).toList();
    List<double> toplamVolum = measurements.map((m) => m.volume).toList();
    List<double> miliSaniye = measurements.map((m) => m.time).toList();

    // Access the latest flow rate directly from the Queue
    double latestFlowRate = measurements.last.flowRate;
    double latestVolume = measurements.last.volume;

    const double threshold = 0.01;

    if (latestFlowRate <= threshold) {
      if (!isGravityActive) {
        _startGravity();
      }
    } else {
      if (isGravityActive) {
        _stopGravity();
      }
    }

    // Calculate FVC
    fvc = _hesaplaFVC(toplamVolum);

    // Calculate FEV1
    fev1 = _hesaplaFEV1(akisHizi, miliSaniye);

    // Calculate PEF
    pef = _hesaplaPEF(akisHizi);

    // Calculate FEV6
    fev6 = _hesaplaFEV6(akisHizi, miliSaniye);

    // Calculate FEF25-75
    fev2575 = _hesaplaFEF2575(akisHizi, toplamVolum);

    // Calculate FEV1/FVC ratio
    fev1Fvc = fvc != 0.0 ? (fev1 / fvc) * 100 : 0.0;

    double fvcPercentage = (fvc / 10.0).clamp(0.0, 1.0);
    _controller.animateTo(
      fvcPercentage,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );

    // Debug: Print calculated metrics
    print('Calculating Metrics...');
    print('FVC: $fvc');
    print('FEV1: $fev1');
    print('PEF: $pef');
    print('FEV6: $fev6');
    print('FEF25-75: $fev2575');
    print('FEV1/FVC: $fev1Fvc%');
  }

  void _startGravity() {
    if (isGravityActive) return; // Prevent multiple timers
    isGravityActive = true;
    gravityDecrement = 0.01; // Reset decrement

    // Start the gravity simulation
    gravityTimer = Timer.periodic(Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        double newValue = _controller.value - gravityDecrement;
        if (newValue <= 0.0) {
          newValue = 0.0;
          timer.cancel();
          isGravityActive = false;
        }
        _controller.value = newValue.clamp(0.0, 1.0);

        // Gradually increase the decrement to simulate acceleration
        gravityDecrement +=
            0.005; // Adjust the increment for desired acceleration
      });
    });
  }

  void _stopGravity() {
    if (gravityTimer != null && gravityTimer!.isActive) {
      gravityTimer!.cancel();
    }
    setState(() {
      isGravityActive = false;
      gravityDecrement = 0.04; // Reset decrement
    });
  }

  /// Calculates Forced Vital Capacity (FVC)
  double _hesaplaFVC(List<double> toplamVolum) {
    if (toplamVolum.isEmpty) return 0.0;
    double maxVolume = toplamVolum.reduce(max);
    double minVolume = toplamVolum.reduce(min);
    return maxVolume - minVolume;
  }

  /// Calculates Forced Expiratory Volume in 1 Second (FEV1)
  double _hesaplaFEV1(List<double> akisHizi, List<double> zaman) {
    if (akisHizi.isEmpty || zaman.isEmpty || akisHizi.length != zaman.length)
      return 0.0;

    double startTime = zaman.first;
    double endTime = startTime + 1000.0; // 1 second in milliseconds
    double totalVolume = 0.0;

    for (int i = 0; i < akisHizi.length - 1; i++) {
      double currentTime = zaman[i];
      double nextTime = zaman[i + 1];

      if (currentTime >= endTime) break;

      double deltaTime =
          (nextTime - currentTime) / 1000.0; // Convert ms to seconds

      if (nextTime > endTime) {
        deltaTime = (endTime - currentTime) / 1000.0;
      }

      totalVolume += akisHizi[i] * deltaTime;
    }

    return totalVolume;
  }

  /// Calculates Forced Expiratory Volume in 6 Seconds (FEV6)
  double _hesaplaFEV6(List<double> akisHizi, List<double> zaman) {
    if (akisHizi.isEmpty || zaman.isEmpty || akisHizi.length != zaman.length)
      return 0.0;

    double startTime = zaman.first;
    double endTime = startTime + 6000.0; // 6 seconds in milliseconds
    double totalVolume = 0.0;

    for (int i = 0; i < akisHizi.length - 1; i++) {
      double currentTime = zaman[i];
      double nextTime = zaman[i + 1];

      if (currentTime >= endTime) break;

      double deltaTime =
          (nextTime - currentTime) / 1000.0; // Convert ms to seconds

      if (nextTime > endTime) {
        deltaTime = (endTime - currentTime) / 1000.0;
      }

      totalVolume += akisHizi[i] * deltaTime;
    }

    return totalVolume;
  }

  /// Calculates Peak Expiratory Flow (PEF)
  double _hesaplaPEF(List<double> akisHizi) {
    return akisHizi.isNotEmpty
        ? akisHizi.reduce((value, element) => value > element ? value : element)
        : 0.0;
  }

  /// Calculates Forced Expiratory Flow at 25–75% (FEF25-75)
  double _hesaplaFEF2575(List<double> akisHizi, List<double> toplamVolum) {
    double fvc = _hesaplaFVC(toplamVolum);
    if (fvc == 0.0) return 0.0;

    double fef25 = 0.0;
    double fef75 = 0.0;
    double volume25 = fvc * 0.25;
    double volume75 = fvc * 0.75;

    for (int i = 0; i < toplamVolum.length; i++) {
      if (toplamVolum[i] >= volume25 && fef25 == 0.0) {
        fef25 = akisHizi[i];
      }
      if (toplamVolum[i] >= volume75 && fef75 == 0.0) {
        fef75 = akisHizi[i];
        break;
      }
    }

    if (fef25 == 0.0 || fef75 == 0.0) return 0.0;

    return (fef25 + fef75) / 2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: Column(
        children: [
          // Timer and Title
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Timer Display
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.orange, width: 3),
                  ),
                  padding: EdgeInsets.all(15),
                  child: Text(
                    '$_timerCount\nSEC',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                // Title
                Text(
                  'Daha Hızlı Daha Kuvvetli!!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Animated Ball within Tube
          Expanded(
            flex: 3,
            child: Center(
              child: Container(
                width: 80,
                height: 450,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.purple[700]!, Colors.purple[900]!],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Animated Ball
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Positioned(
                          bottom: _controller.value *
                              250, // Adjust multiplier as needed
                          child: child!,
                        );
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.orangeAccent,
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Control Buttons
          Expanded(
            flex: 1,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: isAnimating ? null : _startAnimation,
                    child: Text('Teste Başla'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: isAnimating ? _stopAnimation : null,
                    child: Text(
                      'Testi Bitir',
                      style: TextStyle(
                          color: Colors.orange), // Yazı rengini turuncu yap
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Additional Widgets (e.g., Metrics Display) can be added here
        ],
      ),
    );
  }
}
