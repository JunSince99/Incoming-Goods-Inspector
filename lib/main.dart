import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase/firebase_database.dart';
import 'sqlite/sqlite_database.dart';
import 'auto_camera_page.dart';
import 'package:intl/intl.dart';
import 'login_page.dart';


Map<String, bool> isCheckedMap = {}; // 입고 확인 여부
Map<String, List<String>> productBarcodeMap = {}; // 로컬에 저장할 바코드 정보
List<String> fetchedProductCodes = [];
List<String> fetchedProductNames = [];
List<String> fetchedProductQuantities = [];
List<String> isBox = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseDatabase.initializeFirebase();
  await DatabaseHelper.instance.database;

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? username = prefs.getString('username');
  final String? password = prefs.getString('password');

  runApp(MyApp(
    isLoggedIn: username != null && password != null,
  ));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '입고 물품 확인',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const MyHomePage(title: '입고 물품 검수') : LoginPage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  Widget build(BuildContext context) { //UI 부분
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () async {
              final SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.remove('username');
              await prefs.remove('password');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
            child: const Text('로그아웃'),
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const SizedBox(),
            SizedBox(
              width: 300,
              height: 80,
              child: FilledButton(
                onPressed: () async {
                  try {
                    // 로딩 표시
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return const Center(child: CircularProgressIndicator());
                      },
                    );

                    String? currentIncomingDateOfDatabase = await DatabaseHelper.instance.getIncomingDate();
                    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

                    if (currentIncomingDateOfDatabase != todayDate) {
                      // 데이터 초기화
                      await DatabaseHelper.instance.clearAllData();
                      setState(() {
                        isCheckedMap = {};
                        productBarcodeMap = {};
                        fetchedProductCodes = [];
                        fetchedProductNames = [];
                        fetchedProductQuantities = [];
                        isBox = [];
                      });
                    } else {
                      // 데이터 불러오기
                      final checkedData = await DatabaseHelper.instance.getAllIsChecked();
                      final barcodeMapData = await DatabaseHelper.instance.getAllProductBarcodeMap();
                      final productCodesData = await DatabaseHelper.instance.getAllProductCodes();
                      final productNamesData = await DatabaseHelper.instance.getAllProductNames();
                      final productQuantitiesData = await DatabaseHelper.instance.getAllProductQuantities();
                      final isBoxData = await DatabaseHelper.instance.getAllIsBox();

                      setState(() {
                        isCheckedMap = checkedData;
                        productBarcodeMap = barcodeMapData;
                        fetchedProductCodes = productCodesData;
                        fetchedProductNames = productNamesData;
                        fetchedProductQuantities = productQuantitiesData;
                        isBox = isBoxData;
                      });
                    }

                    // 로딩 표시 제거
                    Navigator.of(context).pop();

                    // 모든 데이터 작업이 완료된 후 페이지 이동
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AutoCameraPage()),
                    );
                  } catch (e) {
                    // 오류 처리
                    print('Error: $e');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('데이터 로딩 중 오류가 발생했습니다.')),
                    );
                    // 로딩 표시 제거
                    Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  '입고 물품 체크 시작하기',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
              child: InkWell(
                onTap: () {
                  DatabaseHelper.instance.clearAllData();
                  isCheckedMap = {};
                  productBarcodeMap = {};
                  fetchedProductCodes = [];
                  fetchedProductNames = [];
                  fetchedProductQuantities = [];
                  isBox = [];
                },
                child: const Text(
                  '납품서 데이터 초기화하기',
                  style: TextStyle(
                    color: Color.fromARGB(255, 202, 2, 2),
                    decoration: TextDecoration.underline,
                    decorationColor: Color.fromARGB(255, 202, 2, 2),
                    fontWeight: FontWeight.bold,
                  ),
                )
              ),
            )
          ],
        ),
      ),
    );
  }
}
