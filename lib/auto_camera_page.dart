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

List<CameraDescription> cameras = [];

class AutoCameraPage extends StatefulWidget {
  const AutoCameraPage({super.key});

  @override
  State<AutoCameraPage> createState() => _AutoCameraPageState();
}

class _AutoCameraPageState extends State<AutoCameraPage> {
  late CameraController controller;
  AutoScrollController scrollController = AutoScrollController();
  final TextEditingController _productSearchController =
      TextEditingController();
  List<String> filteredProducts = [];
  bool _isLoading = false;
  bool _isCameraInitialized = false;
  Map<String, List<String>> productBarcodeMap = {}; // 로컬에 저장할 바코드 정보

  @override
  void initState() {
    super.initState();
    initializeCamera();
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
        filteredProducts = fetchedProductCodes;
      } else {
        filteredProducts = fetchedProductCodes.where((code) {
          final name = fetchedProductNames[fetchedProductCodes.indexOf(code)];
          return code.toLowerCase().contains(query) ||
              name.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void scrollToIndex(int index) async {
    await scrollController.scrollToIndex(index,
        preferPosition: AutoScrollPosition.begin);
  }

  void flashItemColor(int index) async {
    //깜빡이기
    for (int i = 0; i < 11; i++) {
      setState(() {
        isChecked[index] = !isChecked[index];
      });
      await Future.delayed(const Duration(milliseconds: 300));
    }
    setState(() {
      isChecked[index] = true;
    });
  }

  Future<void> fetchBarcodes() async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    for (String pdc in fetchedProductCodes) {
      List<String>? barcodes =
          await firebaseDatabase.getBarcodesByProductCode(pdc);
      if (barcodes.isNotEmpty) {
        productBarcodeMap[pdc] = barcodes;
      }
    }
  }

  Future<void> processBarcodes(List<Barcode> barcodes) async {
    //인식된 바코드 납품서와 비교
    bool ismatched = false;
    for (Barcode barcode in barcodes) {
      for (var fpc in fetchedProductCodes) {
        List<String>? otherBarcodes = productBarcodeMap[fpc];

        if (otherBarcodes != null) {
          for (var otherbarcode in otherBarcodes) {
            if (otherbarcode == barcode.rawValue) {
              ismatched = true;
              isChecked[fetchedProductCodes.indexOf(fpc)] = true;
              Vibration.vibrate(duration: 200);
              scrollToIndex(fetchedProductCodes.indexOf(fpc));
              flashItemColor(fetchedProductCodes.indexOf(fpc));
              break;
            }
          }
        }
        if (ismatched) break;
      }
      if (!ismatched) {
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
                    ),
                    SizedBox(
                      height: 500, // 높이를 지정하여 스크롤 가능하도록 함
                      child: ListView.builder(
                        itemCount: filteredProducts.length,
                        itemBuilder: (BuildContext context, int index) {
                          int originalIndex = fetchedProductCodes
                              .indexOf(filteredProducts[index]);
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
                                        '${fetchedProductNames[originalIndex]} 상품에 바코드를 추가합니다'),
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
                                              fetchedProductCodes[
                                                  originalIndex]);
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
                                            fetchedProductNames[originalIndex],
                                            style:
                                                const TextStyle(fontSize: 18),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                        Text(
                                          fetchedProductCodes[originalIndex],
                                          style: const TextStyle(
                                              color: Colors.grey),
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
        );
      }
    }
  }

  void _showErrorDialog(BuildContext context, String message) {
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

  Future<void> addNewProductInDatabase() async {
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

  Future<void> addBarcodeToProduct(String newbcd, String pdtcode) async {
    await FirebaseDatabase().insert("barcode_productcode", newbcd, pdtcode);
    fetchBarcodes();
  }

  Future<void> getIncomingProductList() async {
    setState(() {
      _isLoading = true;
    });

    const url = 'https://selenium-flask-txecraa52a-du.a.run.app/run';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        fetchedProductCodes = (data['item_codes'] ?? []).cast<String>();
        fetchedProductNames = (data['item_names'] ?? []).cast<String>();
        fetchedProductQuantities =
            (data['item_quantities'] ?? []).cast<String>();

        isChecked = List<bool>.filled(fetchedProductCodes.length, false);
        filteredProducts = fetchedProductCodes;

        addNewProductInDatabase();
        await fetchBarcodes();

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
      setState(() {
        _isLoading = false;
      });
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
      isChecked = List<bool>.filled(fetchedProductCodes.length, false);
      filteredProducts = fetchedProductCodes;
      fetchBarcodes();
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
                  FilledButton(
                    // 상품목록조회 페이지 이동 버튼
                    onPressed: () {
                      getIncomingProductList();
                    },
                    child: const Text('납품서 불러오기'),
                  ),
                  const SizedBox(
                    height: 100,
                  ),
                  OutlinedButton(
                    // 상품목록조회 페이지 이동 버튼
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
              Expanded(
                  child: ListView.builder(
                controller: scrollController,
                itemCount: fetchedProductCodes.length,
                itemBuilder: (BuildContext context, int index) {
                  return AutoScrollTag(
                    key: ValueKey(index),
                    controller: scrollController,
                    index: index,
                    child: Card(
                      color:
                          isChecked[index] ? Colors.lightGreen : Colors.white,
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
                                    fetchedProductNames[index],
                                    style: const TextStyle(fontSize: 18),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  )),
                                  Text(fetchedProductCodes[index],
                                      style:
                                          const TextStyle(color: Colors.grey))
                                ],
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  "${fetchedProductQuantities[index]}개",
                                  style: const TextStyle(fontSize: 20),
                                ),
                                const SizedBox(width: 10),
                                isChecked[index]
                                    ? OutlinedButton(
                                        onPressed: () {
                                          setState(() {
                                            isChecked[index] =
                                                !isChecked[index];
                                          });
                                        },
                                        child: const Text("취소"))
                                    : OutlinedButton(
                                        onPressed: () {
                                          setState(() {
                                            isChecked[index] =
                                                !isChecked[index];
                                          });
                                        },
                                        child: const Text("확인"))
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
                      controller.setFlashMode(FlashMode.off);
                      final image = await controller.takePicture();

                      if (!mounted) return;

                      ImageProperties properties =
                          await FlutterNativeImage.getImageProperties(
                              image.path);
                      final targetHeight = properties.height! ~/ 3;
                      final topOffset =
                          (properties.height! - targetHeight) ~/ 2;
                      final imageFile = await FlutterNativeImage.cropImage(
                          image.path,
                          0,
                          topOffset,
                          properties.width!,
                          targetHeight);
                      showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                                title: Text('체크'),
                                content: Image.file(imageFile),
                              ));

                      final inputImage =
                          InputImage.fromFilePath(imageFile.path);
                      final barcodeScanner =
                          BarcodeScanner(formats: [BarcodeFormat.all]);
                      final List<Barcode> barcodes =
                          await barcodeScanner.processImage(inputImage);

                      if (barcodes != []) {
                        await processBarcodes(barcodes);
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