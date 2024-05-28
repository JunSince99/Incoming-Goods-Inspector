import 'dart:io';
import 'package:flutter/material.dart';
import 'package:barcode_checker/product_codes.dart';
import 'package:barcode_checker/product_list.dart';
import 'package:barcode_checker/database_helper.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';

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
  Future<void> _exportDatabaseToCSV() async { //데이터베이스 CSV파일로 안드로이드 download 폴더에 저장하는 함수
    var status = await Permission.storage.status; //스토리지 권한의 권한 상태
    
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }

    if (status.isGranted) {
      DatabaseHelper dbHelper = DatabaseHelper.instance;

      // Products 테이블 데이터를 CSV로 변환
      List<Map<String, dynamic>> products = await dbHelper.getProducts();
      List<List<dynamic>> productRows = [];
      productRows.add(["Product Code", "Product Name"]); // CSV 헤더

      for (var product in products) {
        List<dynamic> row = [];
        row.add(product['product_code']);
        row.add(product['product_name']);
        productRows.add(row);
      }

      String productCsv = const ListToCsvConverter().convert(productRows);
      final directory = Directory('/storage/emulated/0/Download'); // 안드로이드 다운로드 폴더 경로
      final productPath = "${directory.path}/products.csv";
      final File productFile = File(productPath);
      await productFile.writeAsString(productCsv);

      // Barcode 테이블 데이터를 CSV로 변환
      List<Map<String, dynamic>> barcodes = await dbHelper.queryData('Barcode');
      List<List<dynamic>> barcodeRows = [];
      barcodeRows.add(["Barcode", "Product Code"]); // CSV 헤더

      for (var barcode in barcodes) {
        List<dynamic> row = [];
        row.add(barcode['barcode']);
        row.add(barcode['product_code']);
        barcodeRows.add(row);
      }

      String barcodeCsv = const ListToCsvConverter().convert(barcodeRows);
      final barcodePath = "${directory.path}/barcodes.csv";
      final File barcodeFile = File(barcodePath);
      await barcodeFile.writeAsString(barcodeCsv);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("CSV 파일이 다운로드 폴더에 저장되었습니다:\nproducts.csv\nbarcodes.csv")),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("저장 권한이 필요합니다.")),
      );
    }
  }

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
            const SizedBox(
              height: 20,
            ),
            FilledButton(
              onPressed: _exportDatabaseToCSV,
              child: const Text('CSV 파일로 내보내기'),
            ),
          ],
        ),
      ),
    );
  }
}
