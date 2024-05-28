import 'package:flutter/material.dart';
import 'package:barcode_checker/product_codes.dart';
import 'package:barcode_checker/product_list.dart';
import 'firebase/firebase_database.dart';

//이 값들은 앱이 종료될 때까지 유지되어야 하기 때문에 main.dart에서 선언
List<String> extractedTexts = []; //납품서 사진에서 추출된 바코드숫자 리스트
List<MapEntry<String, String>> matchedProducts = []; //납품서에서 인식된 상품 리스트 (바코드,상품명)
List<bool> isChecked = []; // 입고 확인 여부
List<TextEditingController> productCountTextfieldValues = []; //상품 개수 입력란의 값 리스트

void updateProductCountTextfieldValues() { //productCTV의 길이를 matchedProducts와 똑같이 유지시켜주는 함수
  if (productCountTextfieldValues.length < matchedProducts.length) {
    for (var i = productCountTextfieldValues.length; i < matchedProducts.length; i++) {
      productCountTextfieldValues.add(TextEditingController());
    }
  } else if (productCountTextfieldValues.length > matchedProducts.length) { //productCTV가 matchedProducts 보다 길면
    productCountTextfieldValues = productCountTextfieldValues.sublist(0, matchedProducts.length); //인덱스0부터 matchedProducts의 길이만큼 자름
  }
}

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
            FilledButton( // 상품코드스캔 페이지 이동 버튼
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProductCodes()),
                );
              },
              child: const Text('상품 코드 스캔'),
            ),
            FilledButton( // 상품목록조회 페이지 이동 버튼
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProductList()),
                );
              },
              child: const Text('상품 목록 조회'),
            ),
          ],
        ),
      ),
    );
  }
}
