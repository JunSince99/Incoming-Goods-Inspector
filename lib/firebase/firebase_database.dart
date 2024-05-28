import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

class Product {
  final String productCode;
  final String productName;
  final List<String> barcodes;

  Product({
    required this.productCode,
    required this.productName,
    required this.barcodes,
  });
}

class FirebaseDatabase {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<void> initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  Future<List<Product>> fetchProducts() async {
    try {
      // productcode_productname 문서 가져오기
      DocumentSnapshot<Map<String, dynamic>> productCodeNameDoc = await _firestore.collection('ProductsList').doc('productcode_productname').get();
      Map<String, dynamic> productCodeNameData = productCodeNameDoc.data() ?? {};

      // barcode_productcode 문서 가져오기
      DocumentSnapshot<Map<String, dynamic>> barcodeProductCodeDoc = await _firestore.collection('ProductsList').doc('barcode_productcode').get();
      Map<String, dynamic> barcodeProductCodeData = barcodeProductCodeDoc.data() ?? {};

      // 바코드 데이터를 기반으로 productCode - barcodes 매핑 생성
      Map<String, List<String>> productCodeToBarcodes = {};
      barcodeProductCodeData.forEach((barcode, productCode) {
        if (!productCodeToBarcodes.containsKey(productCode)) {
          productCodeToBarcodes[productCode] = [];
        }
        productCodeToBarcodes[productCode]?.add(barcode);
      });

      // Product 리스트 생성
      List<Product> products = [];
      productCodeNameData.forEach((productCode, productName) {
        List<String> barcodes = productCodeToBarcodes[productCode] ?? [];
        products.add(Product(
          productCode: productCode,
          productName: productName,
          barcodes: barcodes,
        ));
      });

      return products;
    } catch (e) {
      print('Error fetching products: $e');
      return [];
    }
  }

  Future<void> insert(String table, String key, String value) async {
    try{
      await _firestore.collection("ProductsList").doc(table).update({
        key:value,
      });
    } catch (e) {
      print("Error adding field: $e");
    }
  }

    Future<void> deleteProduct(String productCode) async {
    try {
      // productcode_productname 문서에서 product code에 해당하는 값 삭제
      DocumentReference productCodeNameDocRef = _firestore.collection('ProductsList').doc('productcode_productname');
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot productCodeNameSnapshot = await transaction.get(productCodeNameDocRef);
        if (productCodeNameSnapshot.exists) {
          Map<String, dynamic> productCodeNameData = productCodeNameSnapshot.data() as Map<String, dynamic>;
          productCodeNameData.remove(productCode);
          transaction.update(productCodeNameDocRef, productCodeNameData);
        }
      });

      // barcode_productcode 문서에서 해당 product code를 값으로 갖는 모든 바코드 삭제
      DocumentReference barcodeProductCodeDocRef = _firestore.collection('ProductsList').doc('barcode_productcode');
      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot barcodeProductCodeSnapshot = await transaction.get(barcodeProductCodeDocRef);
        if (barcodeProductCodeSnapshot.exists) {
          Map<String, dynamic> barcodeProductCodeData = barcodeProductCodeSnapshot.data() as Map<String, dynamic>;
          barcodeProductCodeData.removeWhere((key, value) => value == productCode);
          transaction.update(barcodeProductCodeDocRef, barcodeProductCodeData);
        }
      });

      print("Product and associated barcodes deleted successfully");
    } catch (e) {
      print("Error deleting product: $e");
    }
  }

  Future<String?> getProductNameByBarcode(String barcode) async {
    try {
      // barcode_productcode 문서에서 barcode에 해당하는 productcode를 가져옵니다.
      DocumentSnapshot<Map<String, dynamic>> barcodeProductCodeDoc = await _firestore.collection('ProductsList').doc('barcode_productcode').get();
      Map<String, dynamic>? barcodeProductCodeData = barcodeProductCodeDoc.data();
      
      if (barcodeProductCodeData != null && barcodeProductCodeData.containsKey(barcode)) {
        String productCode = barcodeProductCodeData[barcode] as String;

        // productcode_productname 문서에서 productCode에 해당하는 productName을 가져옵니다.
        DocumentSnapshot<Map<String, dynamic>> productCodeNameDoc = await _firestore.collection('ProductsList').doc('productcode_productname').get();
        Map<String, dynamic>? productCodeNameData = productCodeNameDoc.data();
        
        if (productCodeNameData != null && productCodeNameData.containsKey(productCode)) {
          return productCodeNameData[productCode] as String;
        } else {
          return null; // productCode가 문서에 없는 경우
        }
      } else {
        return null; // barcode가 문서에 없는 경우
      }
    } catch (e) {
      print('Error fetching product name by barcode: $e');
      return null;
    }
  }

    Future<List<String>> getBarcodesByProductCode(String productCode) async {
    try {
      // barcode_productcode 문서에서 모든 데이터를 가져옵니다.
      DocumentSnapshot<Map<String, dynamic>> barcodeProductCodeDoc = await _firestore.collection('ProductsList').doc('barcode_productcode').get();
      Map<String, dynamic>? barcodeProductCodeData = barcodeProductCodeDoc.data();

      if (barcodeProductCodeData != null) {
        // productCode에 해당하는 모든 바코드를 필터링하여 리스트로 만듭니다.
        List<String> barcodes = barcodeProductCodeData.entries
            .where((entry) => entry.value == productCode)
            .map((entry) => entry.key)
            .toList();
        
        return barcodes;
      } else {
        return []; // 데이터가 없는 경우 빈 리스트 반환
      }
    } catch (e) {
      print('Error fetching barcodes by product code: $e');
      return [];
    }
  }
}