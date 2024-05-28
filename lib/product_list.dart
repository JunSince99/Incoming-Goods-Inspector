import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase/firebase_database.dart';

class ProductList extends StatefulWidget {
  @override
  _ProductListState createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  late Future<List<Product>> _productList;
  List<Product> _allProductList = [];
  List<Product> _filteredProductList = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _productCodeController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _newBarcodeController = TextEditingController();
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
    _productNameController.dispose();
    _productCodeController.dispose();
    _barcodeController.dispose();
    _newBarcodeController.dispose();
    super.dispose();
  }

  Future<List<Product>> _fetchProductList() async { //상품 목록 전체 가져오기
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();

    List<Product> productWithBarcodes = await firebaseDatabase.fetchProducts();
    
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
        return product.productName.toLowerCase().contains(query) ||
            product.productCode.toLowerCase().contains(query) ||
            (product.barcodes as List).any((barcode) => barcode.toLowerCase().contains(query));
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

  Future<void> _addProduct() async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    String productName = _productNameController.text.trim();
    String productCode = _productCodeController.text.trim();
    String barcode = _barcodeController.text.trim();

    if (productName.isNotEmpty && productCode.isNotEmpty && barcode.isNotEmpty) {
      
      await firebaseDatabase.insert('productcode_productname', productCode, productName);

      await firebaseDatabase.insert('barcode_productcode', barcode, productCode);

      setState(() {
        _productList = _fetchProductList();
      });

      Navigator.of(context).pop();
    }
  }

  Future<void> _addBarcode(String productCode) async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    String newBarcode = _newBarcodeController.text.trim();

    if (newBarcode.isNotEmpty) {
      await firebaseDatabase.insert('Barcode', newBarcode, productCode);

      setState(() {
        _productList = _fetchProductList();
      });

      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteProduct(String productCode) async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    await firebaseDatabase.deleteProduct(productCode);

    setState(() {
      _productList = _fetchProductList();
    });
  }

  void _provideHapticFeedback() {
    HapticFeedback.mediumImpact();
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
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('새 상품 추가'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _productNameController,
                                decoration: const InputDecoration(
                                  labelText: '상품명',
                                ),
                              ),
                              TextField(
                                controller: _productCodeController,
                                decoration: const InputDecoration(
                                  labelText: '상품코드',
                                ),
                              ),
                              TextField(
                                controller: _barcodeController,
                                decoration: const InputDecoration(
                                  labelText: '바코드',
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                              },
                              child: const Text('취소'),
                            ),
                            TextButton(
                              onPressed: _addProduct,
                              child: const Text('추가'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _startSearch,
                ),
              ],
      ),
      body: FutureBuilder<List<Product>>(
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
                  onLongPress: () {
                    _provideHapticFeedback();
                    showModalBottomSheet(
                      context: context,
                      builder: (context) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ListTile(
                              leading: const Icon(Icons.add),
                              title: const Text('바코드 추가하기'),
                              onTap: () {
                                Navigator.pop(context);
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      title: const Text('바코드 추가'),
                                      content: TextField(
                                        controller: _newBarcodeController,
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
                                          onPressed: () {
                                            _addBarcode(product.productCode);
                                          },
                                          child: const Text('추가'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            ),
                            ListTile(
                              leading: Icon(Icons.delete),
                              title: Text('삭제하기'),
                              onTap: () {
                                Navigator.pop(context);
                                _deleteProduct(product.productCode);
                              },
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          title: Text(product.productName),
                          subtitle: Text(product.productCode),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var barcode in product.barcodes) Text(barcode),
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
