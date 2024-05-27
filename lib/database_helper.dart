import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._instance();
  static Database? _database;

  DatabaseHelper._instance();

  Future<Database> get database async {
    if (_database == null) {
      _database = await _initDatabase();
    }
    return _database!;
  }

  Future<Database> _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'products.db');

    bool dbExists = await databaseExists(path);

    if (!dbExists) {
      return await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          await _createDb(db);
        },
      );
    } else {
      return await openDatabase(path);
    }
  }

  Future<void> _createDb(Database db) async {
    await db.execute('''
      CREATE TABLE Product (
        product_code TEXT PRIMARY KEY,
        product_name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE Barcode (
        barcode TEXT PRIMARY KEY,
        product_code TEXT,
        FOREIGN KEY (product_code) REFERENCES Product(product_code)
      )
    ''');

    await _insertDataFromCSV(db);
  }

  Future<void> _insertDataFromCSV(Database db) async {
    final productData = await rootBundle.loadString('assets/productcode_productname.csv');
    List<List<dynamic>> productList = CsvToListConverter().convert(productData);

    for (var row in productList) {
      await db.insert('Product', {
        'product_code': row[0].toString(),
        'product_name': row[1].toString(),
      });
    }

    final barcodeData = await rootBundle.loadString('assets/barcode_productcode.csv');
    List<List<dynamic>> barcodeList = CsvToListConverter().convert(barcodeData);

    for (var row in barcodeList) {
      if (row[0].toString().isNotEmpty) {
        await db.insert('Barcode', {
          'barcode': row[0].toString(),
          'product_code': row[1].toString(),
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> getProducts() async {
    Database db = await database;
    return await db.query('Product');
  }

  Future<Map<String, dynamic>?> getProductByCode(String productCode) async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query(
      'Product',
      where: 'product_code = ?',
      whereArgs: [productCode],
    );

    if (results.isNotEmpty) {
      return results.first;
    } else {
      return null;
    }
  }

  

  Future<int> insert(String table, Map<String, dynamic> data) async {
    Database db = await database;
    return await db.insert(table, data);
  }

  Future<int> delete(String table, {required String whereClause, required List<dynamic> whereArgs}) async {
    Database db = await database;
    return await db.delete(table, where: whereClause, whereArgs: whereArgs);
  }

  Future<int> updateData(String tableName, Map<String, dynamic> data, String whereClause, List<dynamic> whereArgs) async {
    Database db = await database;
    return await db.update(tableName, data, where: whereClause, whereArgs: whereArgs);
  }

  Future<int> deleteProduct(String productCode) async {
    Database db = await database;
    return await db.delete(
      'Product',
      where: 'product_code = ?',
      whereArgs: [productCode],
    );
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    Database db = await database;
    return await db.query(
      'Product',
      where: 'product_name LIKE ?',
      whereArgs: ['%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> queryData(String tableName, {String? whereClause, List<dynamic>? whereArgs, String? orderBy}) async {
    Database db = await database;
    return await db.query(tableName, where: whereClause, whereArgs: whereArgs, orderBy: orderBy);
  }

  Future<String?> getProductNameByBarcode(String barcode) async {
    Database db = await database;
    final result = await db.query(
      'Barcode',
      columns: ['product_code'],
      where: 'barcode = ?',
      whereArgs: [barcode],
    );

    if (result.isNotEmpty) {
      final productCode = result.first['product_code'];
      final productResult = await db.query(
        'Product',
        columns: ['product_name'],
        where: 'product_code = ?',
        whereArgs: [productCode],
      );

      if (productResult.isNotEmpty) {
        return productResult.first['product_name'] as String?;
      }
    }
    return null;
  }

  Future<String?> getProductCodeByBarcode(String barcode) async {
    Database db = await database;
    List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT product_code
      FROM Barcode
      WHERE barcode = ?
    ''', [barcode]);

    if (result.isNotEmpty) {
      return result.first['product_code'] as String?;
    } else {
      return null;
    }
  }

  

  Future<List<String>?> getOtherBarcodesForProduct(String barcode) async {
    Database db = await database;
    // 상품 코드를 가져옵니다.
    String? productCode = await getProductCodeByBarcode(barcode);
    if (productCode == null) {
      return null;
    }

    // 동일한 상품 코드에 연결된 모든 바코드를 가져옵니다.
    List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT barcode
      FROM Barcode
      WHERE product_code = ?
    ''', [productCode]);

    // 결과에서 바코드를 추출하고, 원래 바코드를 제외한 나머지를 반환합니다.
    List<String> barcodes = result.map((row) => row['barcode'] as String).toList();
    barcodes.remove(barcode);

    if (barcodes.isNotEmpty) {
      return barcodes;
    } else {
      return null;
    }
  }
  Future<List<Map<String, dynamic>>> searchProductsByName(String name) async {
    Database db = await database;
    return await db.query(
      'Product',
      where: 'product_name LIKE ?',
      whereArgs: ['%$name%'],
    );
  }

  Future<void> deleteDatabaseFile() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, 'products.db');

    if (await databaseExists(path)) {
      await deleteDatabase(path);
      print('Database deleted at $path');
    } else {
      print('No database found at $path');
    }
  }
}
