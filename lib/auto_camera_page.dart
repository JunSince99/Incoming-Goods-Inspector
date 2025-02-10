import 'package:barcode_checker/main.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:vibration/vibration.dart';
import 'firebase/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
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
  Set<int> selected = {0};
  int allproductlength = fetchedProductNames.length;
  int leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;

  @override
  void initState() { // 초기화
    super.initState();
    initializeCamera();
    _filterProducts();
    _productSearchController.addListener(_filterProducts);
  }

  Future<void> initializeCamera() async { //카메라 초기화
    try {
      cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        controller = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
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

  void _filterProducts() { //검색 필터
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

  void scrollToIndex(String productId) async { // 해당 productid로 스크롤 이동하는 함수
    int index = fetchedProductCodes.indexOf(productId);
    if (index != -1) {
      await scrollController.scrollToIndex(index, preferPosition: AutoScrollPosition.begin, duration: Duration(milliseconds: 1));
    }
  }


  void flashItemColor(String productId) async { // productid에 해당하는 상품 반짝이는 함수
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
        leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;
      });
    }
  }

  Future<void> fetchAllBarcodes() async { //납품서 목록에 있는 상품의 바코드 서버에서 불러오는 함수
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

  Future<void> fetchBarcode(String productcode) async { // 특정 상품의 바코드 값 서버에서 불러오는 함수
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    List<String> barcodes = await firebaseDatabase.getBarcodesByProductCode(productcode);
    if (barcodes.isNotEmpty) {
      productBarcodeMap[productcode] = barcodes;
      DatabaseHelper.instance.insertProductBarcodes(productcode, barcodes);
    }
  }

  void updateIsChecked(String productId, bool value) async { // productId에 해당하는 상품 checked값 변경하는 함수
    await DatabaseHelper.instance.updateIsCheckedById(productId, value);
    setState(() {
      isCheckedMap[productId] = value;
      leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;
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
              leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;
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
        title: Text(message),
        content: Text("다시 시도해주세요"),
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

    const url = 'https://flask-app-680685794316.asia-northeast3.run.app/run';

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

        if (data.containsKey("error")) {
          _showErrorDialog(context, "ID 또는 비밀번호가 틀렸습니다.");
        } else {
          String prettyJson = const JsonEncoder.withIndent('  ').convert(data);
          prettyJson.split('\n').forEach((line) => logger.i(line));
          fetchedProductCodes = (data['item_codes'] ?? []).cast<String>();
          fetchedProductNames = (data['item_names'] ?? []).cast<String>();
          fetchedProductQuantities =(data['item_quantities'] ?? []).cast<String>();
          List<String> isBoxrawdata = (data['is_box'] ?? []).cast<String>();

          allproductlength = fetchedProductNames.length;
          
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
            leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;
            filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList(); // 초기값 설정
          }); // filteredProducts는 검색된 상품들임 그래서 처음에 전체 상품으로 초기화함
          DatabaseHelper.instance.insertIsCheckedMap(isCheckedMap);

          await addNewProductInDatabase();
          await fetchAllBarcodes();

          if (!mounted) return;
        }
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
        leftproductlength = fetchedProductNames.length - isCheckedMap.values.where((value) => value).length;
      });
      DatabaseHelper.instance.insertIsCheckedMap(isCheckedMap);
      filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList();
      fetchAllBarcodes();
    });
  }

  @override
  Widget build(BuildContext context) {
    const double previewAspectRatio = 0.5;
    if (fetchedProductCodes.isEmpty) {
      return Scaffold(
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
        )
      );
    } else {
      return SafeArea(
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
              Column( // 검색창 + 상자 보기
                children: [
                  Row(
                    children: [
                      Text("전체 상품 수 : "),
                      Text(allproductlength.toString()),
                      Text(" 남은 상품 수 : "),
                      Text(leftproductlength.toString())
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
                  SizedBox(
                    width: 370,
                    height: 50,
                    child: SegmentedButton(
                      multiSelectionEnabled: false,
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 0, label: Text('전체 상품')),
                        ButtonSegment(value: 1, label: Text('상자만')),
                        ButtonSegment(value: 2, label: Text('남은 상품'))
                      ],
                      selected: selected,
                      onSelectionChanged: (Set<int> newSelection) {
                        setState(() {
                          selected = newSelection;

                          if (selected.contains(0)) {
                            filteredProducts = fetchedProductCodes.asMap().entries.map((entry) => {'code': entry.value, 'index': entry.key}).toList();
                          } else if (selected.contains(1)) {
                            filteredProducts = fetchedProductCodes.asMap().entries.where((entry) {
                              return isBox[entry.key] != '0'; // '1'인 항목만 필터링
                            }).map((entry) => {'code': entry.value, 'index': entry.key}).toList();
                          } else if (selected.contains(2)) {
                            filteredProducts = [
                              for (int i = 0; i < fetchedProductCodes.length; i++)
                                if (isCheckedMap[fetchedProductCodes[i]] == false)
                                  {'code': fetchedProductCodes[i], 'index': i},
                            ];
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
              Expanded( // 상품 목록
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fetchedProductNames[productIndex],
                                    style: const TextStyle(fontSize: 18),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                  Text(
                                    productId,
                                    style: const TextStyle(color: Colors.grey),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
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
              SizedBox( // 바코드 찍기 버튼
                width: 350,
                height: 70,
                child: FilledButton(
                  onPressed: () async {
                    controller.setFlashMode(FlashMode.off); // 자동 플래시 끄기
                    final image = await controller.takePicture(); // 사진 찍기

                    img.Image? imageproperties = img.decodeImage(await image.readAsBytes());
                    if(imageproperties == null) {
                      throw Exception("이미지를 불러올 수 없습니다.");
                    }

                    if (imageproperties.width > imageproperties.height) {
                      imageproperties = img.copyRotate(imageproperties,angle: 90); // 90도 회전
                    }

                    int offsetY = (imageproperties.height - (imageproperties.width ~/ 2)) ~/ 2;
                    final croppedimg = img.copyCrop(
                      imageproperties,
                      x: 0,
                      y: offsetY,
                      width: imageproperties.width,
                      height: (imageproperties.width ~/ 2)
                    );

                    final directory = await getTemporaryDirectory(); // 임시 디렉터리 가져오기
                    final filePath = '${directory.path}/cropped_image.png'; // 파일 경로 설정
                    final file = File(filePath);

                    // PNG로 인코딩 후 파일로 저장
                    await file.writeAsBytes(img.encodePng(croppedimg));


                    final inputImage =
                        InputImage.fromFilePath(filePath);
                    final barcodeScanner = BarcodeScanner(formats: [
                      BarcodeFormat.code128,
                      BarcodeFormat.code39,
                      BarcodeFormat.code93,
                      BarcodeFormat.codabar,
                      //BarcodeFormat.dataMatrix,
                      BarcodeFormat.ean13,
                      BarcodeFormat.ean8,
                      BarcodeFormat.itf,
                      BarcodeFormat.upca,
                      BarcodeFormat.upce,
                      //BarcodeFormat.pdf417,
                      //BarcodeFormat.aztec,
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
                    // if (Platform.isAndroid) { // 안드로이드에서 사진 크롭하기
                    //   var cropSize =
                    //       min(properties.width!, properties.height!);
                    //   int offsetX = (properties.width! - (cropSize ~/ 2)) ~/ 2;
                    //   int offsetY = (properties.height! - cropSize) ~/ 2;
                    //   final imageFile = await FlutterNativeImage.cropImage(
                    //       image.path,
                    //       offsetX,
                    //       offsetY,
                    //       (cropSize ~/ 2).toInt(),
                    //       cropSize);

                    //   final inputImage =
                    //       InputImage.fromFilePath(imageFile.path);
                    //   final barcodeScanner = BarcodeScanner(formats: [ // 인식되는 바코드 종류
                    //     BarcodeFormat.code128,
                    //     BarcodeFormat.code39,
                    //     BarcodeFormat.code93,
                    //     BarcodeFormat.codabar,
                    //     BarcodeFormat.ean13,
                    //     BarcodeFormat.ean8,
                    //     BarcodeFormat.itf,
                    //     BarcodeFormat.upca,
                    //     BarcodeFormat.upce,
                    //     BarcodeFormat.pdf417,
                    //     BarcodeFormat.aztec,
                    //   ]);
                    //   final List<Barcode> barcodes =
                    //       await barcodeScanner.processImage(inputImage);
                    //   if (barcodes.isNotEmpty) {
                    //     await processBarcodes(barcodes);
                    //   } else {
                    //     Fluttertoast.showToast(
                    //         msg: "바코드가 인식되지 않았습니다",
                    //         gravity: ToastGravity.TOP);
                    //   }
                    // }
                    // if (Platform.isIOS) { // iOS에서 사진 크롭하기
                    //   final targetHeight = properties.height! ~/ 3;
                    //   final topOffset =
                    //       (properties.height! - targetHeight) ~/ 2;
                    //   final imageFile = await FlutterNativeImage.cropImage(
                    //       image.path,
                    //       0,
                    //       topOffset,
                    //       properties.width!,
                    //       targetHeight);
                    //   // showDialog(
                    //   //     context: context,
                    //   //     builder: (context) => AlertDialog(
                    //   //           title: Text('체크'),
                    //   //           content: Image.file(imageFile),
                    //   //         ));
                    //   final inputImage =
                    //       InputImage.fromFilePath(imageFile.path);
                    //   final barcodeScanner = BarcodeScanner(formats: [ //인식되는 바코드 종류
                    //     BarcodeFormat.code128,
                    //     BarcodeFormat.code39,
                    //     BarcodeFormat.code93,
                    //     BarcodeFormat.codabar,
                    //     BarcodeFormat.ean13,
                    //     BarcodeFormat.ean8,
                    //     BarcodeFormat.itf,
                    //     BarcodeFormat.upca,
                    //     BarcodeFormat.upce,
                    //     BarcodeFormat.pdf417,
                    //     BarcodeFormat.aztec,
                    //   ]);
                    //   final List<Barcode> barcodes =
                    //       await barcodeScanner.processImage(inputImage);

                    //   if (barcodes.isNotEmpty) {
                    //     await processBarcodes(barcodes);
                    //   } else {
                    //     Fluttertoast.showToast(
                    //         msg: "바코드가 인식되지 않았습니다",
                    //         gravity: ToastGravity.TOP);
                    //   }
                    // }
                  },
                  child: const Text(
                    '바코드 찍기',
                    style: TextStyle(fontSize: 25),
                  ),
                ),
              ),
            ],
          )
        )
      );
    }
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