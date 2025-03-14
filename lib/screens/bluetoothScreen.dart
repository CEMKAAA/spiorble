import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spiroble/bluetooth/BluetoothConnectionManager.dart';

class BluetoothScreen extends StatefulWidget {
  @override
  _BluetoothScreenState createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  late BluetoothConnectionManager _bleManager;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    setState(() {});

    _bleManager =
        Provider.of<BluetoothConnectionManager>(context, listen: false);
    _bleManager.connectedDeviceId;

    _bleManager.startScan();
    _loadConnectionState();
    _bleManager.checkConnectionOnLoad();

    if (_bleManager.checkConnecting()) {
      _bleManager.isLoading.value = false;
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
  }

  // Bluetooth bağlantı durumunu yükle
  Future<void> _loadConnectionState() async {
    await _bleManager.loadConnectionState();
    Future.delayed(Duration(seconds: 1), () {
      print("Bağlantı durumu: ${_bleManager.checkConnection()}");
    });
  }

  void _denyConnection() {
    // Implement deny functionality, e.g., stop scanning or navigate back
    _bleManager.stopScan();
    _bleManager.disconnectToDevice(_bleManager.connectedDeviceId!);
    print("BAGLANTIYI KOPARDIK");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bağlantı İptal Edildi')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Consumer<BluetoothConnectionManager>(
            builder: (context, _bleManager, child) {
          return StreamBuilder<List<DiscoveredDevice>>(
              stream: _bleManager.DiscoveredDeviceStream,
              builder: (context, snapshot) {
                // sıkıntı çıkarsa bi bak
                final devices = snapshot.data ?? [];

                final deviceToConnect = devices.firstWhere(
                  (device) => device.name == "Spirometer",
                  orElse: () => DiscoveredDevice(
                    id: "",
                    name: "",
                    manufacturerData: Uint8List(0),
                    serviceData: {},
                    rssi: 0,
                    serviceUuids: [],
                  ),
                );

                return Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    // Header Section
                    Container(
                      padding: EdgeInsets.only(top: 50, bottom: 20),
                      color: Theme.of(context).primaryColor,
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              "Cihazınızı Bağlayın",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            SizedBox(height: 10),
                            Text(
                              "Cihaz bağlama ekranı",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Spacer
                    SizedBox(height: 30),

                    // Main Content
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Illustration Section
                          Image.asset(
                            'assets/bluetooth.png', // Bluetooth resminin adını güncelleyin
                            // Ensure this asset is added in pubspec.yaml
                            width: 180,
                            height: 180,
                            color: Colors.orange,
                          ),

                          SizedBox(height: 20),

                          // Connecting Text
                          Column(
                            children: [
                              SizedBox(height: 10),
                              Text(
                                _bleManager.checkConnection()
                                    ? "Bağlantı başarılı!"
                                    : "Bağlantı yok, tekrar deneyiniz",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 40),

                          // Connection Permission Request
                          Text(
                            "Spiroble cihazı bluetooth light energy teknolojisi kullanır",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bottom Buttons
                    Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment
                            .spaceBetween, // Dikey hizalama için SpaceBetween kullanın
                        children: [
                          // Deny Button
                          OutlinedButton(
                            onPressed: _bleManager.checkConnection()
                                ? _denyConnection
                                : null,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 12),
                              child: Text(
                                "Bağlantıyı durdur",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),

                          // ElevatedButton durumuna bağlı olarak göster/gizle
                          Visibility(
                            visible: !_bleManager
                                .checkConnection(), // Bağlı değilse buton görünür
                            child: ElevatedButton(
                              onPressed: () async {
                                if (_bleManager.checkConnection()) {
                                  _bleManager.isLoading.value = false;
                                } else {
                                  _bleManager.startScan();

                                  if (deviceToConnect.id == null) {
                                    _bleManager.isLoading.value = false;
                                    print("Cihaz bulunamadı");
                                  } else {
                                    await _bleManager
                                        .connectToDevice(deviceToConnect.id);
                                    _bleManager.isLoading.value = false;
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).secondaryHeaderColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                child: Text(
                                  _bleManager.checkConnection()
                                      ? "Bağlantı başarılı!"
                                      : "Bağlan",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              });
        }));
  }
}
