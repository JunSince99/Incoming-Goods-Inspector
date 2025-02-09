import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase/firebase_database.dart';
import 'sqlite/sqlite_database.dart';
import 'auto_camera_page.dart';
import 'package:intl/intl.dart';
import 'login_page.dart';


Map<String, bool> isCheckedMap = {}; // 입고 확인 여부
Map<String, List<String>> productBarcodeMap = {}; // 로컬에 저장할 바코드 정보

// 코레일 사이트에서 크롤링 해온 정보들
List<String> fetchedProductCodes = []; // 상품 코드
List<String> fetchedProductNames = []; // 상품 이름
List<String> fetchedProductQuantities = []; // 상품 수량
List<String> isBox = []; // 음료수 상자인지 여부
//

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 플러터 엔진 초기화 파이어베이스 초기화 하기전에 해야함
  await FirebaseDatabase.initializeFirebase(); // 파이어베이스 데이터베이스 초기화 (서버에서 데이터 가져오기.)
  await DatabaseHelper.instance.database; // 로컬DB sqlite 초기화 (모든 동작마다 서버에 접근할 필요를 줄이기 위해 로컬 db에 저장하고 변경되는 값만 수정하도록 설계함)

  final SharedPreferences prefs = await SharedPreferences.getInstance(); // 아이디 비밀번호 키-값만을 저장하기 위한 sharedPreferences.
  final String? username = prefs.getString('username'); // 저장돼있는 ID 불러오기
  final String? password = prefs.getString('password'); // 저장돼있는 비밀번호 불러오기

  runApp(MyApp( // 플러터를 실행시키는 runApp
    isLoggedIn: username != null && password != null, // 로그인 정보가 로컬에 존재하는지 확인
  ));
}

class MyApp extends StatelessWidget { // 변화 없는 stateless widget
  final bool isLoggedIn;

  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) { // 플러터앱의 가장 토대가 되는 build 위젯
    return MaterialApp( // 머티리얼 스타일의 앱 리턴. platform앱으로 변경해서 ios에선 쿠퍼티노로 적용할 예정
      debugShowCheckedModeBanner: false, // 디버그 딱지 떼는 코드
      title: '입고 물품 확인', // 앱 타이틀
      theme: ThemeData( // 테마. 주요 색과 머티리얼3 적용 여부
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: isLoggedIn ? const MyHomePage(title: '입고 물품 검수') : const LoginPage(), // 로그인 돼있으면 myhomepage, 안돼있으면 로그인 페이지 열기
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
    return Scaffold( // appBar, body로 이루어진 Scaffold. 홈페이지의 가장 기초.
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary, // 테마에서 컬러 가져오기
        title: Text(widget.title), // build위젯의 title 가져오기
        actions: [
          TextButton( // 텍스트 버튼 (로그아웃 버튼)
            onPressed: () async {
              final SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.remove('username');
              await prefs.remove('password'); // 로컬에 저장돼있는 ID와 비밀번호 제거
              Navigator.pushReplacement( // 페이지로 이동 함수
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()), // 로그인 페이지로 이동
              );
            },
            child: const Text('로그아웃'), // 텍스트 버튼의 텍스트
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
                    // showDialog( // 로딩 표시
                    //   context: context,
                    //   barrierDismissible: false,
                    //   builder: (BuildContext context) {
                    //     return const Center(child: CircularProgressIndicator());
                    //   },
                    // );

                    String? currentIncomingDateOfDatabase = await DatabaseHelper.instance.getIncomingDate(); // 로컬 입고 상품 데이터의 입고일 가져오기
                    String todayDate = DateFormat('yyyy-MM-dd').format(DateTime.now()); // 오늘 날짜 가져오기

                    if (currentIncomingDateOfDatabase != todayDate) { // 오늘 날짜의 데이터가 아니라면
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
                    // Navigator.of(context).pop();


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
                  '입고 물품 체크 시작',
                  style: TextStyle(fontSize: 20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
