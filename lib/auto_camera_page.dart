import 'package:barcode_checker/main.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:vibration/vibration.dart';
import 'firebase/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:fluttertoast/fluttertoast.dart';
import 'sqlite/sqlite_database.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

List<CameraDescription> cameras = [];

class AutoCameraPage extends StatefulWidget {
  const AutoCameraPage({super.key});

  @override
  State<AutoCameraPage> createState() => _AutoCameraPageState();
}

class _AutoCameraPageState extends State<AutoCameraPage> {
  late CameraController controller; //카메라 컨트롤러
  AutoScrollController scrollController = AutoScrollController(); //스크롤 컨트롤러
  final TextEditingController _productSearchController = //상품에 바코드 추가창 검색 컨트롤러
      TextEditingController();
  List<Map<String, dynamic>> filteredProducts = <Map<String, dynamic>>[]; //상품에 바코드 추가창 상품 목록
  bool _isLoading = false; //납품서 불러오는 중인지 확인
  bool _isCameraInitialized = false; //카메라 초기화 확인
  bool showBoxOnly = false; //상자만 보기 여부

  @override
  void initState() {
    super.initState();
    initializeCamera();
    _filterProducts();
    _productSearchController.addListener(_filterProducts);
  }

  Future<void> initializeCamera() async {
    //카메라 초기화
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        controller = CameraController(cameras[0], ResolutionPreset.veryHigh);
        await controller.initialize();
        if (!mounted) return;
        setState(() {
          _isCameraInitialized = true;
        });
      } else {
        print('No cameras available');
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  void _filterProducts() {
    final query = _productSearchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList();
      } else {
        filteredProducts = fetchedProductCodes.asMap().entries.where((entry) {
          final code = entry.value;
          final name = fetchedProductNames[entry.key].toLowerCase();
          return code.toLowerCase().contains(query) || name.contains(query);
        }).map((entry) => {'code': entry.value, 'index': entry.key}).toList();
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void scrollToIndex(String productId) async {
    int index = fetchedProductCodes.indexOf(productId);
    if (index != -1) {
      await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.begin);
    }
  }


  void flashItemColor(String productId) async {
    int index = fetchedProductCodes.indexOf(productId);
    if (index != -1) {
      for (int i = 0; i < 11; i++) {
        setState(() {
          isCheckedMap[productId] = !isCheckedMap[productId]!;
        });
        await Future.delayed(const Duration(milliseconds: 300));
      }
      setState(() {
        isCheckedMap[productId] = true;
      });
    }
  }

  Future<void> fetchAllBarcodes() async { //납품서 목록에 있는 바코드 불러오기
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    List<Future<void>> futures = [];

    for (String pdc in fetchedProductCodes) {
      futures.add(
        firebaseDatabase.getBarcodesByProductCode(pdc).then((barcodes) {
          if (barcodes.isNotEmpty) {
            productBarcodeMap[pdc] = barcodes;
            DatabaseHelper.instance.insertProductBarcodes(pdc, barcodes);
          }
        })
      );
    }

    await Future.wait(futures);
  }

  Future<void> fetchBarcode(String productcode) async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    List<String> barcodes = await firebaseDatabase.getBarcodesByProductCode(productcode);
    if (barcodes.isNotEmpty) {
      productBarcodeMap[productcode] = barcodes;
      DatabaseHelper.instance.insertProductBarcodes(productcode, barcodes);
    }
  }

  void updateIsChecked(String productId, bool value) async {
    await DatabaseHelper.instance.updateIsCheckedById(productId, value);
    setState(() {
      isCheckedMap[productId] = value;
    });
  }


  Future<void> processBarcodes(List<Barcode> barcodes) async { //인식된 바코드 처리
    bool ismatched = false;
    for (Barcode barcode in barcodes) {
      for (var fpc in fetchedProductCodes) {
        List<String>? otherBarcodes = productBarcodeMap[fpc];

        if (otherBarcodes != null) {
          for (var otherbarcode in otherBarcodes) {
            if (otherbarcode == barcode.rawValue) {
              ismatched = true;
              isCheckedMap[fpc] = true; //isChecked 값 true로 변경
              await DatabaseHelper.instance.updateIsCheckedById(fpc, true); //isChecked 값 데이터베이스에 저장
              Vibration.vibrate(duration: 200);
              scrollToIndex(fpc);
              flashItemColor(fpc);
              break;
            }
          }
        }
        if (ismatched) break;
      }
      if (!ismatched) { // 인식된 바코드가 납품서에 없을 때
        if (!mounted) return;
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        "방금 찍으신 (${barcode.rawValue}) 상품을 선택해주세요",
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                    TextField(
                      controller: _productSearchController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        filled: true,
                        fillColor: Color.fromARGB(255, 238, 238, 238),
                        contentPadding: EdgeInsets.all(16.0),
                        hintText: '상품명, 상품코드, 바코드로 검색하기',
                        border: InputBorder.none,
                        hintStyle:
                            TextStyle(color: Color.fromARGB(255, 104, 99, 99)),
                      ),
                      style: const TextStyle(color: Colors.black),
                      onChanged: (text) {
                        setState(() {
                          _filterProducts();
                        });
                      },
                    ),
                    SizedBox(
                      height: 500, // 높이를 지정하여 스크롤 가능하도록 함
                      child: ListView.builder(
                        itemCount: filteredProducts.length,
                        itemBuilder: (BuildContext context, int index) {
                          final productMap = filteredProducts[index];
                          final productId = productMap['code'];
                          final productIndex = productMap['index'];
                          
                          return Card(
                            color: Colors.white,
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                //showdialog로 이 상품이 맞습니까? 띄우고
                                //확인시 해당 바코드를 그 상품 상품코드와 함께 데이터베이스에 저장
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                        '${fetchedProductNames[productIndex]} 상품에 바코드를 추가합니다'),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('취소'),
                                      ),
                                      TextButton(
                                        onPressed: () async {
                                          showDialog(
                                              context: context,
                                              builder: (context) =>
                                                  const AlertDialog(
                                                      title:
                                                          Text('바코드 저장중...')));
                                          await addBarcodeToProduct(
                                              barcode.rawValue.toString(),
                                              productId
                                          );
                                          Navigator.of(context).pop();
                                          Navigator.of(context).pop();
                                          Navigator.of(context).pop();
                                        },
                                        child: const Text('확인'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 15, 15, 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          child: Text(
                                            fetchedProductNames[productIndex],
                                            style:
                                                const TextStyle(fontSize: 18),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        Text(
                                          productId,
                                          style: const TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ).whenComplete(() {
          _productSearchController.clear();
        });
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) { //납품서 불러오기 실패시 띄우는 창
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('불러오기 실패!!\n다시 시도해주세요'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  Future<void> addNewProductInDatabase() async { //데이터베이스에 없는 상품 추가
    Map<String, dynamic>? barcodeProductCodeData =
        await FirebaseDatabase().getDatabaseDoc("productcode_productname");

    if (barcodeProductCodeData != null && barcodeProductCodeData != {}) {
      for (String pdc in fetchedProductCodes) {
        if (!barcodeProductCodeData.containsKey(pdc)) {
          FirebaseDatabase().insert("productcode_productname", pdc,
              fetchedProductNames[fetchedProductCodes.indexOf(pdc)]);
        }
      }
    }
  }

  Future<void> addBarcodeToProduct(String newbcd, String pdtcode) async { //상품에 바코드 추가
    await FirebaseDatabase().insert("barcode_productcode", newbcd, pdtcode);
    fetchBarcode(pdtcode);
  }

  Future<void> getIncomingProductList() async { //납품서 불러오기(상품코드, 상품명, 수량)
    setState(() {
      _isLoading = true;
    });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? username = prefs.getString('username');
    final String? password = prefs.getString('password');
    print('username: \'$username\', password: \'$password\'');
    var logger = Logger();

    const url = 'https://flask-app-txecraa52a-du.a.run.app/run';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, String>{
          'username': username ?? '',
          'password': password ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        String prettyJson = const JsonEncoder.withIndent('  ').convert(data);
        prettyJson.split('\n').forEach((line) => logger.i(line));
        fetchedProductCodes = (data['item_codes'] ?? []).cast<String>();
        fetchedProductNames = (data['item_names'] ?? []).cast<String>();
        fetchedProductQuantities =(data['item_quantities'] ?? []).cast<String>();
        List<String> isBoxrawdata = (data['is_box'] ?? []).cast<String>();
        
        isBox = isBoxrawdata.map((quantity) {
          return int.parse(quantity) >= 20 ? '1' : '0';
        }).toList();

        DatabaseHelper.instance.insertFetchedProductCodes(fetchedProductCodes);
        DatabaseHelper.instance.insertFetchedProductNames(fetchedProductNames);
        DatabaseHelper.instance.insertFetchedProductQuantities(fetchedProductQuantities);
        DatabaseHelper.instance.insertIncomingDate(DateFormat('yyyy-MM-dd').format(DateTime.now()));
        DatabaseHelper.instance.insertIsBox(isBox);
        
        setState(() {
          isCheckedMap = {for (var code in fetchedProductCodes) code: false}; // isCheckedMap 초기화
          filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList(); // 초기값 설정
        }); // filteredProducts는 검색된 상품들임 그래서 처음에 전체 상품으로 초기화함
        DatabaseHelper.instance.insertIsCheckedMap(isCheckedMap);

        await addNewProductInDatabase();
        await fetchAllBarcodes();

        if (!mounted) return;
      } else {
        if (!mounted) return;
        fetchedProductCodes = [];
        fetchedProductNames = [];
        fetchedProductQuantities = [];
        _showErrorDialog(context, 'Error: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      fetchedProductCodes = [];
      fetchedProductNames = [];
      fetchedProductQuantities = [];
      _showErrorDialog(context, 'Error: $e');
    } finally {
      if (mounted){
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> getSampleProductList() async {
    setState(() {
      fetchedProductCodes = [
        "7026118",
        "7026120",
        "8007043",
        "8020728",
        "8025917",
        "8047438",
        "8048765",
        "8050553",
        "8053496",
        "7026814",
        "7030269",
        "7044666",
        "8017429",
        "8018135",
        "8023693",
        "8028150",
        "8028151",
        "8037415",
        "8048883",
        "8051831",
        "8052363",
        "7012711",
        "7015208",
        "7044940",
        "8025458",
        "8042535",
        "7047248",
        "8020494",
        "8051345",
        "7040118",
        "8050892"
      ];
      fetchedProductNames = [
        "코카)글라소파워씨500ML",
        "코카)글라소에너지500ML",
        "코카)모과생강280ML",
        "코카)토레타500ML",
        "코카)코카콜라제로250ML",
        "코카)갈아만든배340ml",
        "코카)몬스터에너지제로슈거355ML",
        "코카)조지아저칼로리라떼470ML",
        "코카)몬스터에너지피치킨355ML",
        "롯데)크런키",
        "롯데)목캔디파워허브",
        "롯데)빈츠",
        "롯데)빅크런키",
        "롯데)후라보노",
        "롯데)자일리톨알파(용기)",
        "롯데)청포도캔디",
        "롯데)애니타임밀크민트",
        "롯데)왓따청포도",
        "롯데)제로크런치초코볼",
        "롯데)졸음번쩍오리지널(코팅)",
        "롯데)제로쿠앤크샌드",
        "광동)비타500(100ML)",
        "광동)옥수수수염차340ML",
        "광동)제주삼다수500ML",
        "광동)비타500젤리48g",
        "광동)비타500 치어팩",
        "엠큐)프링글스양파맛110g(대)",
        "메비우스 스카이블루(곽)",
        "메비우스 스카이블루 롱스",
        "진주)천하장사50g",
        "진주)건강하닭할라피뇨치즈"
      ];
      fetchedProductQuantities = [
        "12",
        "12",
        "6",
        "24",
        "30",
        "6",
        "6",
        "6",
        "24",
        "12",
        "12",
        "2",
        "8",
        "90",
        "6",
        "2",
        "4",
        "16",
        "8",
        "12",
        "2",
        "100",
        "20",
        "40",
        "10",
        "6",
        "1",
        "50",
        "20",
        "16",
        "10"
      ];
      isBox = [
        "1",
        "1",
        "0",
        "1",
        "1",
        "0",
        "0",
        "0",
        "1",
        "0",
        "0",
        "0",
        "0",
        "1",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "1",
        "1",
        "1",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0",
        "0"
      ];
      DatabaseHelper.instance.insertFetchedProductCodes(fetchedProductCodes);
      DatabaseHelper.instance.insertFetchedProductNames(fetchedProductNames);
      DatabaseHelper.instance.insertFetchedProductQuantities(fetchedProductQuantities);
      DatabaseHelper.instance.insertIncomingDate(DateFormat('yyyy-MM-dd').format(DateTime.now()));
      DatabaseHelper.instance.insertIsBox(isBox);
      setState(() {
        isCheckedMap = {for (var code in fetchedProductCodes) code: false}; 
      });
      DatabaseHelper.instance.insertIsCheckedMap(isCheckedMap);
      filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList();;
      fetchAllBarcodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    const double previewAspectRatio = 0.5;
    return fetchedProductCodes.isEmpty
        ? Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              title: const Text(""),
            ),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _isLoading == false
                      ? const Text('20초 정도가 소요됩니다')
                      : const Column(
                          children: [
                            CircularProgressIndicator(),
                            Text("불러오는 중... 잠시만 기다려주세요")
                          ],
                        ),
                  FilledButton( // 상품목록조회 페이지 이동 버튼
                    onPressed: () {
                      getIncomingProductList();
                    },
                    child: const Text('납품서 불러오기'),
                  ),
                  const SizedBox(
                    height: 100,
                  ),
                  OutlinedButton( // 상품목록조회 페이지 이동 버튼
                    onPressed: () {
                      getSampleProductList();
                    },
                    child: const Text('납품서 샘플'),
                  ),
                ],
              ),
            ))
        : SafeArea(
            child: Scaffold(
                body: Column(
            children: [
              _isCameraInitialized
                  ? AspectRatio(
                      //카메라 화면
                      aspectRatio: 1 / previewAspectRatio,
                      child: ClipRect(
                        child: Transform.scale(
                          scale:
                              controller.value.aspectRatio / previewAspectRatio,
                          child: Center(
                            child: CameraPreview(controller),
                          ),
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: SearchBar(
                        leading: const Icon(Icons.search),
                        trailing: [
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _productSearchController.clear();
                              _filterProducts();
                              FocusScope.of(context).unfocus();
                            },
                          ),
                        ],
                        controller: _productSearchController,
                        hintText: '상품 검색',
                        onChanged: (value) {
                          _filterProducts();
                        },
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        showBoxOnly = !showBoxOnly;
                        if (showBoxOnly) {
                          filteredProducts = fetchedProductCodes.asMap().entries.where((entry) {
                            return isBox[entry.key] != '0'; // '1'인 항목만 필터링
                          }).map((entry) => {'code': entry.value, 'index': entry.key}).toList();
                        } else {
                          filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList();
                        }
                      });
                    },
                    child: Text(showBoxOnly ? '납품서 보기' : '상자만 보기'),
                  ),
                ],
              ),
              Expanded(
                  child: ListView.builder(
                controller: scrollController,
                itemCount: filteredProducts.length,
                itemBuilder: (BuildContext context, int index) {
                  final productMap = filteredProducts[index];
                  final productId = productMap['code'];
                  final productIndex = productMap['index'];
                  final isChecked = isCheckedMap[productId] ?? false; // null일 경우 false로 처리

                  return AutoScrollTag(
                    key: ValueKey(index),
                    controller: scrollController,
                    index: index,
                    child: Card(
                      color:
                          isChecked ? Colors.lightGreen : Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 15, 12, 15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 220,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      child: Text(
                                    fetchedProductNames[productIndex],
                                    style: const TextStyle(fontSize: 18),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  )),
                                  Text(productId,
                                      style:
                                          const TextStyle(color: Colors.grey))
                                ],
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "${fetchedProductQuantities[productIndex]}개",
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () async {
                                    updateIsChecked(productId, !isChecked);
                                  },
                                  child: Text(isChecked ? "취소" : "확인")
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )),
              SizedBox(
                // 바코드 찍기 버튼
                width: 350,
                height: 70,
                child: FilledButton(
                  onPressed: () async {
                    try {
                      controller.setFlashMode(FlashMode.off); // 자동 플래시 끄기
                      final image = await controller.takePicture(); // 사진 찍기

                      if (!mounted) return;
                      ImageProperties properties = await FlutterNativeImage.getImageProperties(image.path); 

                      if (Platform.isAndroid) { // 안드로이드에서 사진 크롭하기
                        var cropSize =
                            min(properties.width!, properties.height!);
                        int offsetX =
                            (properties.width! - (cropSize ~/ 2)) ~/ 2;
                        int offsetY = (properties.height! - cropSize) ~/ 2;
                        final imageFile = await FlutterNativeImage.cropImage(
                            image.path,
                            offsetX,
                            offsetY,
                            (cropSize ~/ 2).toInt(),
                            cropSize);

                        final inputImage =
                            InputImage.fromFilePath(imageFile.path);
                        final barcodeScanner = BarcodeScanner(formats: [ // 인식되는 바코드 종류
                          BarcodeFormat.code128,
                          BarcodeFormat.code39,
                          BarcodeFormat.code93,
                          BarcodeFormat.codabar,
                          BarcodeFormat.ean13,
                          BarcodeFormat.ean8,
                          BarcodeFormat.itf,
                          BarcodeFormat.upca,
                          BarcodeFormat.upce,
                          BarcodeFormat.pdf417,
                          BarcodeFormat.aztec,
                        ]);
                        final List<Barcode> barcodes =
                            await barcodeScanner.processImage(inputImage);
                        if (barcodes.isNotEmpty) {
                          await processBarcodes(barcodes);
                        } else {
                          Fluttertoast.showToast(
                              msg: "바코드가 인식되지 않았습니다",
                              gravity: ToastGravity.TOP);
                        }
                      }
                      if (Platform.isIOS) { // iOS에서 사진 크롭하기
                        final targetHeight = properties.height! ~/ 3;
                        final topOffset =
                            (properties.height! - targetHeight) ~/ 2;
                        final imageFile = await FlutterNativeImage.cropImage(
                            image.path,
                            0,
                            topOffset,
                            properties.width!,
                            targetHeight);
                        // showDialog(
                        //     context: context,
                        //     builder: (context) => AlertDialog(
                        //           title: Text('체크'),
                        //           content: Image.file(imageFile),
                        //         ));
                        final inputImage =
                            InputImage.fromFilePath(imageFile.path);
                        final barcodeScanner = BarcodeScanner(formats: [ //인식되는 바코드 종류
                          BarcodeFormat.code128,
                          BarcodeFormat.code39,
                          BarcodeFormat.code93,
                          BarcodeFormat.codabar,
                          BarcodeFormat.ean13,
                          BarcodeFormat.ean8,
                          BarcodeFormat.itf,
                          BarcodeFormat.upca,
                          BarcodeFormat.upce,
                          BarcodeFormat.pdf417,
                          BarcodeFormat.aztec,
                        ]);
                        final List<Barcode> barcodes =
                            await barcodeScanner.processImage(inputImage);

                        if (barcodes.isNotEmpty) {
                          await processBarcodes(barcodes);
                        } else {
                          Fluttertoast.showToast(
                              msg: "바코드가 인식되지 않았습니다",
                              gravity: ToastGravity.TOP);
                        }
                      }
                    } catch (e) {
                      print(e);
                    }
                  },
                  child: const Text(
                    '바코드 찍기',
                    style: TextStyle(fontSize: 25),
                  ),
                ),
              ),
              const SizedBox(height: 4)
            ],
          )));
  }
}



// incoming_products 비어있으면 불러오는 창 나오기 - 완료
// 오늘 입고 물건 불러오기 버튼 - 완료
// 누르면 로딩 - 완료
// 완료되면 카메라 페이지로 이동 - 완료

// 상품명        바코드
// 상품코드      바코드

// 이런 형식으로 불러오고 상품코드 조회해서 데이터베이스에 없는 상품이면 자동으로 추가(상온 상품인지 확인해야함!!) - 완료
// 바코드 인식 되고 맞는 상품 있으면 그쪽으로 이동, 숫자 입력 기능
// 바코드가 인식 됐는데 맞는 상품이 없으면 인식돼있는 상품에서 검색해서 선택