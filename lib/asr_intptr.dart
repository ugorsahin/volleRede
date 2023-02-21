import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tflite_flutter_helper/tflite_flutter_helper.dart';

class ASRModel {
  InterpreterOptions _interpreterOptions = InterpreterOptions();
  late Interpreter interpreter;
  int sampleRate = 16000;
  List<String> alphabet = " abcdefghijklmnopqrstuvwxyz'".split('');

  ASRModel() {
    Interpreter.fromAsset("model_quantized.tflite", options: _interpreterOptions).then((value) {
      interpreter = value;
    }).catchError((e) {
        print('Error loading model: ' + e.toString());
    });
  }

  Future<Int16List> readPCM16(String? filepath, {bool assets=false}) async {
    late Int16List _signal;
    if (filepath != null) {
      final fileBytes = await File(filepath).readAsBytes();
      _signal = Int16List.view(ByteData.sublistView(fileBytes).buffer, 44);
    } else {
      ByteData byteData = await rootBundle.load('assets/test.wav');
      _signal = Int16List.view(byteData.buffer, 44);
    }
    return _signal;
  }

  List<double> normalize(Int16List _signal){
    return _signal.map((i) => i.toDouble() / 32768).toList();
  }

  List<double> processInput(List<double> signal) {
    int totalWindowSize = (signal.length / 320).floor();

    TensorAudio tensorAudio = TensorAudio.create(
        TensorAudioFormat.create(1, sampleRate), signal.length);
    tensorAudio.loadDoubleList(signal);

    TensorBuffer inputBuffer = tensorAudio.tensorBuffer;
    TensorBuffer probabilityBuffer =
    TensorBuffer.createFixedSize([1, totalWindowSize, 29], TfLiteType.float32);

    interpreter.resizeInputTensor(0, inputBuffer.shape);

    interpreter.run(inputBuffer.buffer, probabilityBuffer.buffer);

    return probabilityBuffer.getDoubleList();
  }

  int argmax(List<double> liste) {
    double listmax = liste.reduce(max);
    for(int i=0; i<liste.length; i++){
      if (liste[i] == listmax)
        return i;
    }
    return -1;
  }

  List<String> out2text(List<double> probabilityMatrix) {
    List<String> strlist = List.empty(growable: true);

    int _prevResult = 99;
    int _repeatingEmpty = 0;
    int totalWindowSize = probabilityMatrix.length ~/ 29;
    strlist.add("");
    for(int i=0; i<totalWindowSize; i++){
      int _argmax = argmax(probabilityMatrix.sublist(i*29, i*29 + 29));
      if (_argmax == 28) {
        _repeatingEmpty++;
      } else {
        if (_repeatingEmpty >= 30) {
          if (strlist.last.length != 0)
            strlist.add("");
        }
        _repeatingEmpty = 0;
      }
      if (_argmax != 28 && _argmax !=_prevResult) {
        _prevResult = _argmax;
        if (strlist.last.length == 0)
          strlist.last += alphabet[_argmax].toUpperCase();
        else
          strlist.last += alphabet[_argmax];
      }
    }
    return strlist;
  }

  Future<List<String>> processFile(filepath) async {
    Int16List rawSignal = await readPCM16(filepath);
    List<double> signal = normalize(rawSignal);
    List<double> probMatrix = processInput(signal);
    List<String> text = out2text(probMatrix);
    for (var line in text) {
      print(line);
    }
    return text;
  }
}