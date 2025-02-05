import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const boolType = 'BOOLEAN NOT NULL';

    await db.execute('''
CREATE TABLE productBarcodeMap (
  product $textType,
  barcode $textType UNIQUE
)
''');

    await db.execute('''
CREATE TABLE fetchedProductCodes (
  id $idType,
  code $textType
)
''');

    await db.execute('''
CREATE TABLE fetchedProductNames (
  id $idType,
  name $textType
)
''');

    await db.execute('''
CREATE TABLE fetchedProductQuantities (
  id $idType,
  quantity $textType
)
''');

    await db.execute('''
CREATE TABLE isChecked (
  productId $textType PRIMARY KEY,
  isChecked $boolType
)
''');

    await db.execute('''
CREATE TABLE isBox (
  id $idType,
  isBox $textType
)
''');

  await db.execute('''
CREATE TABLE incomingDate (
  date TEXT PRIMARY KEY
)
''');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  Future<void> resetDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'app_database.db');
    await deleteDatabase(path); // 데이터베이스 삭제
    _database = await _initDB('app_database.db'); // 데이터베이스 다시 생성
  }

  // isChecked 관련 함수들
  Future<void> updateIsCheckedById(String productId, bool value) async {
    final db = await instance.database;
    await db.update(
      'isChecked',
      {'isChecked': value ? 1 : 0},
      where: 'productId = ?',
      whereArgs: [productId],
    );
  }

  Future<void> resetIsChecked(List<String> productIds) async {
    final db = await instance.database;
    await db.delete('isChecked');
    for (String productId in productIds) {
      await db.insert('isChecked', {'productId': productId, 'isChecked': 0});
    }
  }


  Future<Map<String, bool>> getAllIsChecked() async {
    final db = await instance.database;
    final result = await db.query('isChecked');
    return {for (var e in result) e['productId'] as String: e['isChecked'] == 1};
  }

  Future<void> insertIsCheckedMap(Map<String, bool> isCheckedMap) async {
    final db = await instance.database;
    await db.delete('isChecked'); // 기존 데이터를 삭제

    final batch = db.batch(); // Batch를 사용하여 다수의 삽입 작업을 일괄 수행
    isCheckedMap.forEach((productId, isChecked) {
      batch.insert(
        'isChecked',
        {'productId': productId, 'isChecked': isChecked ? 1 : 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true); // Batch 커밋
  }


  // productBarcodeMap 관련 함수들
  Future<void> insertProductBarcodes(String product, List<String> barcodes) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      for (String barcode in barcodes) {
        await txn.insert(
          'productBarcodeMap',
          {'product': product, 'barcode': barcode},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<Map<String, List<String>>> getAllProductBarcodeMap() async { //productBarcodeMap 값 전체 get
    final db = await instance.database;
    final result = await db.query('productBarcodeMap');
    final map = <String, List<String>>{};
    for (var row in result) {
      final product = row['product'] as String;
      final barcode = row['barcode'] as String;
      if (!map.containsKey(product)) {
        map[product] = [];
      }
      map[product]!.add(barcode);
    }
    return map;
  }

  // fetchedProductCodes 관련 함수들
  Future<List<String>> getAllProductCodes() async { //fetchedProductCodes 값 전체 get
    final db = await instance.database;
    final result = await db.query('fetchedProductCodes', columns: ['code']);
    return result.map((row) => row['code'] as String).toList();
  }

  Future<void> insertFetchedProductCodes(List<String> codes) async { //fetchedProductCodes 값 전체 insert
    final db = await instance.database;
    await db.delete('fetchedProductCodes');
    for (var code in codes) {
      await db.insert('fetchedProductCodes', {'code': code});
    }
  }

  // fetchedProductNames 관련 함수들
  Future<List<String>> getAllProductNames() async { //fetchedProductNames 값 전체 get
    final db = await instance.database;
    final result = await db.query('fetchedProductNames', columns: ['name']);
    return result.map((row) => row['name'] as String).toList();
  }

  Future<void> insertFetchedProductNames(List<String> names) async { //fetchedProductNames 값 전체 insert
    final db = await instance.database;
    await db.delete('fetchedProductNames');
    for (var name in names) {
      await db.insert('fetchedProductNames', {'name': name});
    }
  }

  // fetchedProductQuantities 관련 함수들
  Future<List<String>> getAllProductQuantities() async { //fetchedProductQuantities 값 전체 get
    final db = await instance.database;
    final result = await db.query('fetchedProductQuantities', columns: ['quantity']);
    return result.map((row) => row['quantity'] as String).toList();
  }

  Future<void> insertFetchedProductQuantities(List<String> quantities) async { //fetchedProductQuantities 값 전체 insert
    final db = await instance.database;
    await db.delete('fetchedProductQuantities');
    for (var quantity in quantities) {
      await db.insert('fetchedProductQuantities', {'quantity': quantity});
    }
  }

  // isBox 관련 함수들
  Future<List<String>> getAllIsBox() async {
    final db = await instance.database;
    final result = await db.query('isBox');
    return result.map((row) => row['isBox'] as String).toList();
  }

  Future<void> insertIsBox(List<String> isBox) async {
    final db = await instance.database;
    await db.delete('isBox'); // 기존 데이터를 삭제

    for (var code in isBox) {
      await db.insert('isBox',{'isBox': code});
    }
  }

  // incomingDate 관련 함수들
  Future<void> insertIncomingDate(String date) async { //납품서 날짜 저장
    final db = await instance.database;
    await db.delete('incomingDate'); // 기존 값 삭제
    await db.insert('incomingDate', {'date': date}); // 새로운 값 삽입
  }

  Future<String?> getIncomingDate() async { //납품서 날짜 가져오기
    final db = await instance.database;
    final result = await db.query('incomingDate', limit: 1); // 값 가져오기

    if (result.isNotEmpty) {
      return result.first['date'] as String;
    } else {
      return null; // 값이 없을 경우 null 반환
    }
  }

  // 값 전체 초기화
  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('productBarcodeMap');
    await db.delete('fetchedProductCodes');
    await db.delete('fetchedProductNames');
    await db.delete('fetchedProductQuantities');
    await db.delete('isChecked');
    await db.delete('isBox');
    await db.delete('incomingDate');
  }
}