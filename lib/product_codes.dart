import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:barcode_checker/main.dart';
import 'firebase/firebase_database.dart';
import 'camera_page.dart';

class ProductCodes extends StatefulWidget {
  @override
  _ProductCodesState createState() => _ProductCodesState();
}

class _ProductCodesState extends State<ProductCodes> {
  final List<File> _photos = []; //납품서 사진들

  // 사진찍고 크롭해서 photos에 저장해주는 함수
  Future<void> _pickAndCropImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        aspectRatioPresets: [
          CropAspectRatioPreset.square,
          CropAspectRatioPreset.ratio3x2,
          CropAspectRatioPreset.original,
          CropAspectRatioPreset.ratio4x3,
          CropAspectRatioPreset.ratio16x9
        ],
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '자르기',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false
          ),
        ]
      );

      if (croppedFile != null) { 
        final File imageFile = File(croppedFile.path);
        setState(() {
          _photos.add(imageFile);
        });
      }
    }
  }

  // 납품서 사진에서 텍스트 뽑아오는 함수
  Future<void> extractTextFromImages() async {
    final textRecognizer = TextRecognizer();

    for (File photo in _photos) {
      final RecognizedText recognizedText = await textRecognizer.processImage(InputImage.fromFile(photo));

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          // 각 라인에서 공백을 제거하고 저장
          String text = line.text.replaceAll(' ', '');
          extractedTexts.add(text);
        }
      }
    }

    await textRecognizer.close();
  }

  //인식된 납품서로 상품명 불러오기
  Future<void> matchProducts() async {
    FirebaseDatabase firebaseDatabase = FirebaseDatabase();
    List<MapEntry<String, String>> tempmatchedProducts = matchedProducts;

    for (String text in extractedTexts) {
      bool isthere = false;
      for (var temp in matchedProducts) {
        if (temp.key == text) isthere = true;
      }

      if (!isthere) {
        String? productName = await firebaseDatabase.getProductNameByBarcode(text);
        if (productName != null) {
          tempmatchedProducts.add(MapEntry(text, productName));
          isChecked.add(false);
        } else {
          tempmatchedProducts.add(MapEntry(text, '미등록 상품'));
          isChecked.add(false);
        }
      }
    }

    if (mounted) {
      setState(() {
        matchedProducts = tempmatchedProducts;
        updateProductCountTextfieldValues();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('납품서 상품코드'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickAndCropImage,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: () async {
              // 저장된 사진에서 상품코드 뽑아서 저장하기.
              await extractTextFromImages();
              // 상품코드로 상품명 불러오기
              await matchProducts();
              // 바코드 스캔으로 넘어가기
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CameraApp()),
                );
              }
            },
          )
        ],
      ),
      body: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:  3, // 열의 수를 지정
        ),
        itemCount: _photos.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.all(4.0),
            child: Image.file(_photos[index]),
          );
        },
      ),
    );
  }
}
