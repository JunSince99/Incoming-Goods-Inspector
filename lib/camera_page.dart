import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_native_image/flutter_native_image.dart';
import 'dart:math';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:barcode_checking/main.dart';
import 'package:vibration/vibration.dart';
import 'database_helper.dart';
import 'package:flutter/services.dart';

List<CameraDescription> cameras = [];
List<String?> scannedBarcodes = [];

Future<XFile> takeapicture(CameraController controller) async {
  final XFile file = await controller.takePicture();
  return file;
}

class CameraApp extends StatefulWidget {
  @override
  _CameraAppState createState() => _CameraAppState();
}

class _CameraAppState extends State<CameraApp> {
  late CameraController controller;
  final ScrollController scrollController = ScrollController();
  bool _isCameraInitialized = false;
  int? _selectedIndex;  // 선택된 인덱스를 저장할 변수
  final List<GlobalKey> _itemKeys = []; // 각 아이템의 키를 저장할 리스트

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
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

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void scrollToIndex(int index) {
    final keyContext = _itemKeys[index].currentContext;
    if (keyContext != null) {
      Scrollable.ensureVisible(keyContext,
          duration: const Duration(seconds: 1), curve: Curves.easeInOut);
    }
  }

  void flashItemColor(int index) async {
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

  Future<void> processBarcodes(List<Barcode> barcodes) async {
    for (Barcode barcode in barcodes) {
      for (var prdtcode in matchedProducts) {
        List<String>? otherBarcodes = await DatabaseHelper.instance.getOtherBarcodesForProduct(prdtcode.key);

        if (prdtcode.key == barcode.rawValue) {
          isChecked[matchedProducts.indexOf(prdtcode)] = true;
          Vibration.vibrate(duration: 200);
          scrollToIndex(matchedProducts.indexOf(prdtcode));
          flashItemColor(matchedProducts.indexOf(prdtcode));
        }
        if (otherBarcodes != null) {
          for (var otherbarcode in otherBarcodes) {
            if (otherbarcode == barcode.rawValue) {
              isChecked[matchedProducts.indexOf(prdtcode)] = true;
              Vibration.vibrate(duration: 200);
              scrollToIndex(matchedProducts.indexOf(prdtcode));
              flashItemColor(matchedProducts.indexOf(prdtcode));
            }
          }
        }
      }
    }
  }

  void _showOptionsDialog(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('옵션 선택'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('잘못 인식된 바코드 수정'),
                onTap: () {
                  Navigator.of(context).pop(); // Close the current dialog
                  TextEditingController barcodeController = TextEditingController(text: matchedProducts[index].key);
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: const Text('바코드 수정'),
                        content: TextField(
                          controller: barcodeController,
                          decoration: const InputDecoration(
                            labelText: '바코드 번호',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final newBarcode = barcodeController.text;
                              final newProductName = await DatabaseHelper.instance.getProductNameByBarcode(newBarcode);

                              setState(() {
                                matchedProducts[index] = MapEntry(newBarcode, newProductName ?? '미등록 상품');
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('저장'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              ListTile(
                title: Text('상품 등록'),
                onTap: () {
                  Navigator.of(context).pop(); // Close the current dialog
                  setState(() {
                    _selectedIndex = index;  // 선택된 인덱스 저장
                  });
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return Dialog(
                        child: ProductListDialog(
                          onProductSelected: (product) {
                            _addBarcodeToProduct(product);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('닫기'),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _addBarcodeToProduct(Map<String, dynamic> product) async {
    if (_selectedIndex == null) return;

    String barcode = matchedProducts[_selectedIndex!].key;
    String productCode = product['product_code'];

    await DatabaseHelper.instance.insert('Barcode', {
      'barcode': barcode,
      'product_code': productCode,
    });

    setState(() {
      matchedProducts[_selectedIndex!] = MapEntry(barcode, product['product_name']);
    });

    _selectedIndex = null;
  }

  void _provideHapticFeedback() {
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    const double previewAspectRatio = 0.5;
    if (!_isCameraInitialized || !controller.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text('Camera App'),
        ),
        body: Center(
          child: Text('No camera available or failed to initialize.'),
        ),
      );
    }
    return SafeArea(
      child: Scaffold(
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 1 / previewAspectRatio,
              child: ClipRect(
                child: Transform.scale(
                  scale: controller.value.aspectRatio / previewAspectRatio,
                  child: Center(
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: matchedProducts.length,
                itemBuilder: (BuildContext context, int index) {
                  if (_itemKeys.length <= index) {
                    _itemKeys.add(GlobalKey());
                  }
                  return Card(
                    key: _itemKeys[index], // 각 아이템에 고유의 키를 설정
                    color: isChecked[index] ? Colors.lightGreen : Colors.white,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onLongPress: matchedProducts[index].value == '미입력 상품'
                          ? () {
                              _provideHapticFeedback();
                              _showOptionsDialog(context, index);
                            }
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 15, 15, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(matchedProducts[index].value, style: const TextStyle(fontSize: 18)),
                                Text(matchedProducts[index].key, style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                            SizedBox(
                              width: 60,
                              height: 50,
                              child: TextField(
                                controller: productCountTextfieldValues[index],
                                style: const TextStyle(fontSize: 20),
                                textAlign: TextAlign.center,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 10.0),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 350,
              height: 70,
              child: FilledButton(
                onPressed: () async {
                  try {
                    controller.setFlashMode(FlashMode.off);
                    final image = await takeapicture(controller);

                    if (!mounted) return;

                    ImageProperties properties = await FlutterNativeImage.getImageProperties(image.path);
                    var cropSize = min(properties.width!, properties.height!);
                    int offsetX = (properties.width! - (cropSize ~/ 2)) ~/ 2;
                    int offsetY = (properties.height! - cropSize) ~/ 2;
                    final imageFile = await FlutterNativeImage.cropImage(image.path, offsetX, offsetY, (cropSize ~/ 2).toInt(), cropSize);

                    final inputImage = InputImage.fromFilePath(imageFile.path);
                    final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
                    final List<Barcode> barcodes = await barcodeScanner.processImage(inputImage);

                    await processBarcodes(barcodes);

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
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }
}

class ProductListDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onProductSelected;

  ProductListDialog({required this.onProductSelected});

  @override
  _ProductListDialogState createState() => _ProductListDialogState();
}

class _ProductListDialogState extends State<ProductListDialog> {
  late Future<List<Map<String, dynamic>>> _productList;
  List<Map<String, dynamic>> _allProductList = [];
  List<Map<String, dynamic>> _filteredProductList = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _productList = _fetchProductList();
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchProductList() async {
    DatabaseHelper dbHelper = DatabaseHelper.instance;
    List<Map<String, dynamic>> products = await dbHelper.getProducts();

    List<Map<String, dynamic>> productWithBarcodes = [];
    for (var product in products) {
      List<Map<String, dynamic>> barcodes = await dbHelper.queryData(
        'Barcode',
        whereClause: 'product_code = ?',
        whereArgs: [product['product_code']],
      );
      productWithBarcodes.add({
        'product_code': product['product_code'],
        'product_name': product['product_name'],
        'barcodes': barcodes.map((b) => b['barcode']).toList(),
      });
    }

    setState(() {
      _allProductList = productWithBarcodes;
      _filteredProductList = _allProductList;
    });

    return productWithBarcodes;
  }

  void _filterProducts() {
    String query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProductList = _allProductList.where((product) {
        return product['product_name'].toLowerCase().contains(query) ||
            product['product_code'].toLowerCase().contains(query) ||
            (product['barcodes'] as List).any((barcode) => barcode.toLowerCase().contains(query));
      }).toList();
    });
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _stopSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _filteredProductList = _allProductList;
    });
  }

  void _showConfirmationDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('해당 상품에 바코드를 추가하시겠습니까?'),
          content: Text('선택한 상품: ${product['product_name']}'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('취소'),
            ),
            TextButton(
              onPressed: () {
                widget.onProductSelected(product);
                Navigator.of(context).pop(); // Close the confirmation dialog
                Navigator.of(context).pop(); // Close the ProductListDialog
              },
              child: Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '상품명, 상품코드, 바코드로 검색하기',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Color.fromARGB(255, 104, 99, 99)),
                ),
                style: const TextStyle(color: Colors.black),
              )
            : const Text('상품 목록'),
        actions: _isSearching
            ? [
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _stopSearch,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _startSearch,
                ),
              ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _productList,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No products found.'));
          }

          return ListView.builder(
            itemCount: _filteredProductList.length,
            itemBuilder: (context, index) {
              var product = _filteredProductList[index];
              return Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    _showConfirmationDialog(product);
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: Text('${product['product_name']}'),
                          subtitle: Text('${product['product_code']}'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var barcode in product['barcodes']) Text(barcode),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
