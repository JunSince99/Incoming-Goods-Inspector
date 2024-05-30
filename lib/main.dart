import 'package:flutter/material.dart';
import 'firebase/firebase_database.dart';
import 'auto_camera_page.dart';

//이 값들은 앱이 종료될 때까지 유지되어야 하기 때문에 main.dart에서 선언
List<bool> isChecked = []; // 입고 확인 여부

List<String> fetchedProductCodes = [];
List<String> fetchedProductNames = [];
List<String> fetchedProductQuantities = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseDatabase.initializeFirebase();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '입고 물품 확인',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '입고 물품 검수'),
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
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: 300,
              height: 80,
              child: FilledButton( // 상품코드스캔 페이지 이동 버튼
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AutoCameraPage()),
                  );
                },
                child: const Text(
                  '입고 물품 체크 시작하기',
                  style: TextStyle(fontSize: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
