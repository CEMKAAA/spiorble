import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_database/firebase_database.dart';

class HealthMonitorScreen extends StatefulWidget {
  final Map<String, dynamic> measurement;
  final String TestId;

  HealthMonitorScreen({
    required this.measurement,
    required this.TestId,
  });

  @override
  _HealthMonitorScreenState createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen> {
  bool showGraph = false;
  late Future<Map<String, List<double>>> flowRateAndVolumeData;

  @override
  void initState() {
    super.initState();
    flowRateAndVolumeData = fetchFlowRatesAndVolumes(); // Veriyi yükle
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sonuçlarım'),
        centerTitle: true,
        backgroundColor: Color(0xFF3A2A6B),
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF3A2A6B),
              Color(0xFF2E235A),
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                ),
                SizedBox(height: 20),
                Text(
                  'Tarih: ${widget.measurement['timestamp']}',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                SizedBox(height: 20),
                buildMeasurementRow(widget.measurement),
                SizedBox(height: 30),
                buildSymptomsSection(),
                SizedBox(height: 30),
                Center(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding:
                          EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                    ),
                    child: Text('Add Symptoms'),
                  ),
                ),
                SizedBox(height: 30),
                FutureBuilder<Map<String, List<double>>>(
                  // Flowrate ve Volume verilerini getiren FutureBuilder
                  future: flowRateAndVolumeData,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Error loading data'));
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Center(child: Text('No data available'));
                    } else {
                      Map<String, List<double>> data = snapshot.data!;
                      List<double> flowRates = data['flowRates'] ?? [];
                      List<double> volumes = data['volumes'] ?? [];

                      // Flow rate ve volume arasındaki oranı hesapla
                      List<double> ratioData = [];
                      for (int i = 0;
                          i < flowRates.length && i < volumes.length;
                          i++) {
                        if (volumes[i] != 0) {
                          ratioData.add(flowRates[i] / volumes[i]);
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Flow Rate / Volume Ratio',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                          SizedBox(height: 20),
                          Container(
                            height: 200,
                            child: LineChart(
                              LineChartData(
                                gridData: FlGridData(show: true),
                                titlesData: FlTitlesData(show: true),
                                borderData: FlBorderData(show: true),
                                minX: 0,
                                maxX: flowRates.length.toDouble(),
                                minY: 0,
                                maxY: flowRates.isNotEmpty
                                    ? flowRates
                                            .reduce((a, b) => a > b ? a : b) *
                                        1.2 // Yüksek değeri %20 fazla al
                                    : 1, // Eğer veri yoksa, 1'i limit olarak kullan
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: flowRates
                                        .asMap()
                                        .entries
                                        .map((entry) => FlSpot(
                                            entry.key.toDouble(), entry.value))
                                        .toList(),
                                    isCurved: true,
                                    color: Colors.green,
                                    belowBarData: BarAreaData(show: false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),
                SizedBox(height: 30),
                buildMonthlySummary(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, List<double>>> fetchFlowRatesAndVolumes() async {
    List<double> flowRates = [];
    List<double> volumes = [];

    // Get the current user ID from Firebase Authentication
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('User is not logged in');
      return {'flowRates': flowRates, 'volumes': volumes};
    }

    String userId = currentUser.uid; // Get the user ID

    // Reference the correct path using the user ID
    DatabaseReference ref = FirebaseDatabase.instance
        .ref('sonuclar/$userId/tests/${widget.TestId}');

    DataSnapshot snapshot = await ref.get();
    print(snapshot.exists);

    if (snapshot.exists) {
      // Since it's a Map, we cast it to Map<dynamic, dynamic>
      Map<dynamic, dynamic> testData = snapshot.value as Map<dynamic, dynamic>;

      // Check if measurements exist and are not null
      if (testData['measurements'] != null) {
        // Get the list of measurements
        List<dynamic> measurements = testData['measurements'];

        // Iterate over the list of measurements and process flowRates and volumes
        for (var measurementData in measurements) {
          // Only process the flowRate and volume for this specific test
          if (measurementData['flowRate'] != null) {
            flowRates.add(measurementData['flowRate'].toDouble());
          }
          if (measurementData['volume'] != null) {
            volumes.add(measurementData['volume'].toDouble());
          }
        }
      }
    } else {
      print('Veri bulunamadı');
    }

    print(flowRates);
    print(volumes);

    return {'flowRates': flowRates, 'volumes': volumes};
  }

  Widget buildMeasurementRow(Map<String, dynamic> measurement) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: [
        buildMeasurementCard('FVC', measurement['fvc'].toString(), 0.7),
        buildMeasurementCard('FEV1', measurement['fev1'].toString(), 0.9),
        buildMeasurementCard('PEF', measurement['pef'].toString(), 1.0),
        buildMeasurementCard('FEV6', measurement['fev6'].toString(), 0.9),
        buildMeasurementCard(
            'FEV2575', measurement['fef2575'].toString(), 0.85),
        buildMeasurementCard(
            'FEV1/FVC', measurement['fev1Fvc'].toString(), 0.95),
      ],
    );
  }

  Widget buildMeasurementCard(String title, String value, double percent) {
    return Container(
      width: 100,
      child: Column(
        children: [
          CircularPercentIndicator(
            radius: 50.0,
            lineWidth: 5.0,
            animation: true,
            percent: percent,
            center: Text(
              value,
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
            ),
            footer: Text(
              title,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            circularStrokeCap: CircularStrokeCap.round,
            backgroundColor: Colors.grey.shade800,
            progressColor: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget buildSymptomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSymptomRow('Wheezing', 0.5),
        SizedBox(height: 10),
        buildSymptomRow('Breathlessness', 0.3),
      ],
    );
  }

  Widget buildSymptomRow(String symptom, double severity) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          symptom,
          style: TextStyle(color: Colors.white),
        ),
        SizedBox(height: 5),
        LinearProgressIndicator(
          value: severity,
          backgroundColor: Colors.grey.shade800,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
      ],
    );
  }

  Widget buildMonthlySummary() {
    List<double> monthlyData = [
      0.2,
      0.3,
      0.8,
      0.5,
      0.6,
      0.4,
      0.7,
      0.9,
      0.3,
      0.4,
      0.7,
      0.6
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MONTH SUMMARY',
          style: TextStyle(color: Colors.white, fontSize: 14),
        ),
        SizedBox(height: 10),
        Container(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: monthlyData.map((value) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 20,
                      height: 50 * value,
                      decoration: BoxDecoration(
                        color: value > 0.5 ? Colors.purple : Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
