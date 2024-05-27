import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database_helper.dart';

class ProductList extends StatefulWidget {
  @override
  _ProductListState createState() => _ProductListState();
}

class _ProductListState extends State<ProductList> {
  late Future<List<Map<String, dynamic>>> _productList;
  List<Map<String, dynamic>> _allProductList = [];
  List<Map<String, dynamic>> _filteredProductList = [];
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

  Future<void> _addProduct() async {
    DatabaseHelper dbHelper = DatabaseHelper.instance;

    String productName = _productNameController.text.trim();
    String productCode = _productCodeController.text.trim();
    String barcode = _barcodeController.text.trim();

    if (productName.isNotEmpty && productCode.isNotEmpty && barcode.isNotEmpty) {
      await dbHelper.insert('Product', {
        'product_code': productCode,
        'product_name': productName,
      });

      await dbHelper.insert('Barcode', {
        'barcode': barcode,
        'product_code': productCode,
      });

      setState(() {
        _productList = _fetchProductList();
      });

      Navigator.of(context).pop();
    }
  }

  Future<void> _addBarcode(String productCode) async {
    DatabaseHelper dbHelper = DatabaseHelper.instance;
    String newBarcode = _newBarcodeController.text.trim();

    if (newBarcode.isNotEmpty) {
      await dbHelper.insert('Barcode', {
        'barcode': newBarcode,
        'product_code': productCode,
      });

      setState(() {
        _productList = _fetchProductList();
      });

      Navigator.of(context).pop();
    }
  }

  Future<void> _deleteProduct(String productCode) async {
    DatabaseHelper dbHelper = DatabaseHelper.instance;

    await dbHelper.delete('Product', whereClause: 'product_code = ?', whereArgs: [productCode]);
    await dbHelper.delete('Barcode', whereClause: 'product_code = ?', whereArgs: [productCode]);

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
                          title: Text('새 상품 추가'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: _productNameController,
                                decoration: InputDecoration(
                                  labelText: '상품명',
                                ),
                              ),
                              TextField(
                                controller: _productCodeController,
                                decoration: InputDecoration(
                                  labelText: '상품코드',
                                ),
                              ),
                              TextField(
                                controller: _barcodeController,
                                decoration: InputDecoration(
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
                              child: Text('취소'),
                            ),
                            TextButton(
                              onPressed: _addProduct,
                              child: Text('추가'),
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
                                            _addBarcode(product['product_code']);
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
                                _deleteProduct(product['product_code']);
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
