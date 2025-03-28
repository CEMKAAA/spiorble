import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spiroble/bluetooth/bluetooth_constant.dart';

class BluetoothConnectionManager with ChangeNotifier {
  // StreamController'lar
  final _connectionController = StreamController<bool>.broadcast();
  final _deviceController = StreamController<String?>.broadcast();

  // Bağlantı durumu ve cihaz kimliği için yerel değişkenler
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _connectedDeviceId;

   ValueNotifier<bool> isLoading = ValueNotifier(false);

  // Stream'ler (Dinleyicilere veri sağlar)
  Stream<bool> get connectionStream => _connectionController.stream;
  Stream<String?> get deviceStream => _deviceController.stream;

  // Getter'lar (Mevcut durumu sorgulamak için)
  bool checkConnection() => _isConnected;
  bool checkConnecting() => _isConnecting;
  String? get connectedDeviceId => _connectedDeviceId;

  void checkConnectionOnLoad() async{


    if (_isConnected) {
      print("Cihaz bağlı: $_connectedDeviceId");
    } else {
      print("Cihaz bağlantısı kesik.");
    }

    // Bağlantı durumunu dinlemek için stream kullanabilirsiniz
    connectionStream.listen((isConnected) {
      if (isConnected) {
        print("Bağlantı yeniden kuruldu: $_connectedDeviceId");
      } else {
        print("Bağlantı kesildi.");
      }
    });
  }

  // Bağlantı durumunu ayarlama ve kontrolü
  void setConnectionState(String? deviceId, bool connected) {
    _connectedDeviceId = deviceId;
    _isConnected = connected;
    saveConnectionState();

    // Yeni durumları akışlara ekle
    _deviceController.sink.add(_connectedDeviceId);
    _connectionController.sink.add(_isConnected);
    notifyListeners();
  }

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  final StreamController<List<DiscoveredDevice>> _deviceStreamController =
      StreamController.broadcast();

  Stream<List<DiscoveredDevice>> get DiscoveredDeviceStream =>
      _deviceStreamController.stream;

  final List<DiscoveredDevice> _devices = [];
  late QualifiedCharacteristic _characteristic;

  // izinleri ayarlama ve düzenleme
  Future<bool> _checkPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    for (var permission in permissions) {
      if (await permission.request().isDenied) {
        print("${permission.value} izni verilmedi.");
        return false;
      }
    }
    print("Tüm izinler verildi.");
    return true;
  }

  //listelemek için streame ekliyoruz
  void _addDeviceToStream(DiscoveredDevice device) {
    if (!_devices.any((d) => d.id == device.id)) {
      _devices.add(device);
      _deviceStreamController.add(List.unmodifiable(_devices));
    }
  }

  //TARAMAYI BAŞLATIYORUZ
  Future<void> startScan() async {
    isLoading.value = true;

    print("Tarama başlatılıyor...");
    _scanSubscription = _ble.scanForDevices(withServices: []).listen(
      (device) {
        _addDeviceToStream(device);
        isLoading.value = true;
      },
      onError: (error) {
        print("Tarama sırasında hata oluştu: $error");
        isLoading.value = false;
      },
      onDone: () {
        print("Tarama tamamlandı.");
        isLoading.value = false;
      },
    );
  }

  //Taramayı durduruyoruz                         TEKRAR BAKILACAK ŞU ANLIK İLK ÇALIŞMA BEKLENİYOR
  void stopScan() {
    print("Tarama durduruluyor...");
    _scanSubscription?.cancel();
    _scanSubscription = null;
    isLoading.value = false;
  }

  void _startReceivingData() {
    print("Veri alımı başlatılıyor...");
    _ble.subscribeToCharacteristic(_characteristic).listen(
      (data) {
        print('Alınan veri: $data');
      },
      onError: (error) {
        print("Veri alımı sırasında hata oluştu: $error");
      },
    );
  }

  Future<void> initializeCommunication(String deviceId) async {
    Uuid serviceUuid =
        Uuid.parse(BleUuids.initializeCommunicationServiceCharacteristicUuid);
    Uuid characteristicUuid =
        Uuid.parse(BleUuids.initializeCommunicationServiceCharacteristicUuid);

    _characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    try {
      final response = await _ble.readCharacteristic(_characteristic);
      print('İlk veri: $response');

      if (response.isNotEmpty && response[0] == 1) {
        _startReceivingData();
      }
    } catch (error) {
      print("Veri okuma sırasında hata oluştu: $error");
    }
  }

  //ne yaptığını bilmiyorum      İLERİDE TEKRAR KONTROL EDİLECEK
  Future<void> initializeCharacteristic(
      String deviceId, String serviceUuid, String characteristicUuid) async {
    try {
      // Attempt to parse the UUIDs
      Uuid serviceUuidParsed = Uuid.parse(serviceUuid);
      Uuid characteristicUuidParsed = Uuid.parse(characteristicUuid);

      // Initialize the characteristic
      _characteristic = QualifiedCharacteristic(
        deviceId: deviceId,
        serviceId: serviceUuidParsed,
        characteristicId: characteristicUuidParsed,
      );
      print("Characteristic initialized successfully.");
    } catch (e) {
      print("Error parsing UUIDs: $e");
    }
  }

  Stream<List<double>> notifyAsDoubles(String deviceId) {
    Uuid serviceUuid = Uuid.parse(BleUuids.notifyServiceUuid);
    Uuid characteristicUuid = Uuid.parse(BleUuids.notifycharacteristicUuid);

    final characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    // Karakteristikten gelen bildirimleri dinle ve özel formatı çözümle
    return _ble.subscribeToCharacteristic(characteristic).map((data) {
      try {
        // Veriyi string olarak çöz
        final rawString = utf8.decode(data);

        // Süslü parantez kontrolü
        if (!rawString.startsWith("{") || !rawString.endsWith("}")) {
          throw Exception("Beklenmeyen veri formatı: $rawString");
        }

        // Süslü parantezleri temizle
        final trimmed = rawString.substring(1, rawString.length - 1);

        // Boşluklara dikkat ederek ayrıştırma
        final values = trimmed.split(",").map((value) {
          return double.parse(value.trim());
        }).toList();

        // Üç değer bekleniyor, hata kontrolü
        if (values.length != 3) {
          throw Exception("Beklenmeyen veri uzunluğu: $values");
        }

        return values;
      } catch (error) {
        throw Exception("Veri ayrıştırma hatası: $error");
      }
    });
  }

  Future<void> uid3(String deviceId) async {
    Uuid serviceUuid = Uuid.parse(
        BleUuids.Uuid3Services); // D72FDD71-D631-4381-841B-B695DA002032
    Uuid characteristicUuid = Uuid.parse(
        BleUuids.Uuid3Characteristic); // F8C87645-5A2E-40CF-9B22-30D72089DF2B

    print('Servis UUID: $serviceUuid');
    print('Karakteristik UUID: $characteristicUuid');

    _characteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );

    try {
      final response = await _ble.readCharacteristic(_characteristic);
      print('Üçüncü veri: $response');

      if (response.isNotEmpty && response[0] == 1) {
        _startReceivingData();
      }
    } catch (error) {
      print("Veri okuma sırasında hata oluştu: $error");
    }
  }

  // Bağlantı durumu ve cihaz ID'sini kaydet
  Future<void> saveConnectionState() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isConnected', _isConnected);
    prefs.setString('connectedDeviceId', _connectedDeviceId ?? '');
  }

  // Bağlantı durumu ve cihaz ID'sini yükle
  Future<void> loadConnectionState() async {
    final prefs = await SharedPreferences.getInstance();
    _isConnected = prefs.getBool('isConnected') ?? false;
    _connectedDeviceId = prefs.getString('connectedDeviceId');
    notifyListeners();
  }

  Future<void> connectToDevice(String deviceId) async {
    print("Cihaza bağlanılıyor: $deviceId");
    _connectionSubscription = _ble.connectToDevice(id: deviceId).listen(
      (connectionState) async {
        print("Bağlantı durumu: ${connectionState.connectionState}");
        if (connectionState.connectionState ==
            DeviceConnectionState.connected) {
          print("Bağlantı başarılı: $deviceId");
          setConnectionState(deviceId, true);
          notifyListeners();
          isLoading.value = false;

          await Future.delayed(const Duration(seconds: 1)); // Gecikme ekleyin
          await initializeCommunication(deviceId);
        } else if (connectionState.connectionState ==
            DeviceConnectionState.disconnected) {
          setConnectionState(deviceId, false);
          print("Cihaz bağlantısı kesildi: $deviceId");
          isLoading.value = false;
          notifyListeners();
        }
      },
      onError: (error) {
        print("Bağlantı sırasında hata oluştu: $error");
        isLoading.value = false;
      },
    );
  }

  //Silinecek ileride
  Future<void> disconnectToDevice(String deviceId) async {
    try {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      print("Cihaz bağlantısı başarıyla kesildi: $deviceId");
      setConnectionState(deviceId, false); // Bağlantı durumu güncellendi
      isLoading.value = false;
      notifyListeners();
      deviceId = '';
    } catch (error) {
      print("Cihaz bağlantısı kesilirken hata oluştu: $error");
      setConnectionState(deviceId, true);
      isLoading.value = false;
      notifyListeners();
    }
  }

  Future<void> sendChar1(
      String serviceUuid, String characteristicUuid, String deviceId) async {
    try {
      // UUID'leri Uuid formatına çevir
      Uuid parsedServiceUuid = Uuid.parse(serviceUuid);
      Uuid parsedCharacteristicUuid = Uuid.parse(characteristicUuid);

      // Karakteristiği tanımla
      _characteristic = QualifiedCharacteristic(
        serviceId: parsedServiceUuid,
        characteristicId: parsedCharacteristicUuid,
        deviceId: deviceId, // Daha önce bağlanılan cihaz ID'si
      );

      print("Sending char '1' to characteristic: $_characteristic");

      // UTF-8 formatında '1' karakterini byte array olarak hazırla
      final valueToSend = utf8.encode('1'); // [49]

      // Karakteristiğe yaz
      await _ble.writeCharacteristicWithResponse(
        _characteristic,
        value: valueToSend,
      );

      print("Char '1' gönderildi!");
    } catch (error) {
      print("Error sending char '1': $error");
    }
  }

  void dispose() {
    print("Kaynaklar temizleniyor...");
    _scanSubscription?.cancel();
    _deviceController.close();
  }

// Kaynakları serbest bırakma
}
