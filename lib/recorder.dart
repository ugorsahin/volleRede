/*
 * Copyright 2018, 2019, 2020, 2021 Dooboolab.
 *
 * This file is part of Flutter-Sound.
 *
 * Flutter-Sound is free software: you can redistribute it and/or modify
 * it under the terms of the Mozilla Public License version 2 (MPL2.0),
 * as published by the Mozilla organization.
 *
 * Flutter-Sound is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * MPL General Public License for more details.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vollerede/asr_intptr.dart';

int argmax(List<double> liste) {
  double listmax = liste.reduce(max);
  for (int i = 0; i < liste.length; i++) {
    if (liste[i] == listmax) return i;
  }
  return -1;
}

const int tSampleRate = 16000;

typedef _Fn = void Function();

class RecordToStreamExample extends StatefulWidget {
  @override
  _RecordToStreamExampleState createState() => _RecordToStreamExampleState();
}

class _RecordToStreamExampleState extends State<RecordToStreamExample> {
  FlutterSoundPlayer? soundPlayer = FlutterSoundPlayer();
  FlutterSoundRecorder? soundRecorder = FlutterSoundRecorder();
  bool isPlayerInitialized = false;
  bool isRecorderInitialized = false;
  bool isPlaybackReady = false;
  String? soundFilePath;
  StreamSubscription? recordingDataSub;
  List<String> recognitionOut = [];
  String currentStep = "Record to start";
  ASRModel model = ASRModel();

  Future<void> _recognizeSound() async {
    model.processFile(soundFilePath).then((value) {
      recognitionOut = value;
      print("finished");
      print(recognitionOut);
    }).catchError((e) {
      print('Error processing signal: ' + e.toString());
    });
    setState(() {});
  }

  Future<void> _openRecorder() async {
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }
    await soundRecorder!.openRecorder();

    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory:
        AVAudioSessionCategory.playAndRecord,
      avAudioSessionCategoryOptions:
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.defaultToSpeaker,
      avAudioSessionMode:
        AVAudioSessionMode.spokenAudio,
      avAudioSessionRouteSharingPolicy:
        AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions:
        AVAudioSessionSetActiveOptions.none,
      androidAudioAttributes:
        const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
      androidAudioFocusGainType:
        AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    setState(() {
      isRecorderInitialized = true;
    });
  }

  @override
  void initState() {
    super.initState();
    soundPlayer!.openPlayer().then((value) {
      setState(() {
        isPlayerInitialized = true;
      });
    });
    _openRecorder();
  }

  @override
  void dispose() {
    stopPlayer();
    soundPlayer!.closePlayer();
    soundPlayer = null;

    stopRecorder();
    soundRecorder!.closeRecorder();
    soundRecorder = null;

    super.dispose();
  }

  Future<IOSink> createFile() async {
    var tempDir = await getTemporaryDirectory();
    soundFilePath = '${tempDir.path}/flutter_sound_example.pcm';
    var outputFile = File(soundFilePath!);
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    return outputFile.openWrite();
  }

  Future<void> record() async {
    assert(isRecorderInitialized && soundPlayer!.isStopped);
    var sink = await createFile();
    var recordingDataController = StreamController<Food>();
    recordingDataSub =
      recordingDataController.stream.listen((buffer) {
      if (buffer is FoodData)
        sink.add(buffer.data!);
    });

    await soundRecorder!.startRecorder(
      toStream: recordingDataController.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: tSampleRate,
    );
    setState(() {});
  }

  Future<void> stopRecorder() async {
    await soundRecorder!.stopRecorder();
    if (recordingDataSub != null) {
      await recordingDataSub!.cancel();
      recordingDataSub = null;
    }
    isPlaybackReady = true;
  }

  Future<void> stopPlayer() async {
    await soundPlayer!.stopPlayer();
  }

  void play() async {
    assert(isPlayerInitialized && isPlaybackReady && soundRecorder!.isStopped && soundPlayer!.isStopped);
    await soundPlayer!.startPlayer(
      fromURI: soundFilePath,
      sampleRate: tSampleRate,
      codec: Codec.pcm16,
      numChannels: 1,
      whenFinished: () {setState(() {});}
    );
  }

  _Fn? getRecorderFn() {
    if (!isRecorderInitialized || !soundPlayer!.isStopped) {
      return null;
    }
    return soundRecorder!.isStopped
      ? record
      : () {
        stopRecorder().then((value) => setState(() {}));
      };
  }

  _Fn? getPlaybackFn() {
    if (!isPlayerInitialized || !isPlaybackReady || !soundRecorder!.isStopped) {
      return null;
    }
    return soundPlayer!.isStopped
      ? play
      : () {
        stopPlayer().then((value) => setState(() {}));
      };
  }

  _Fn? recognizeSound() {
    return _recognizeSound;
  }

  @override
  Widget build(BuildContext context) {
    BoxDecoration generalBoxes = BoxDecoration(
      color: Color.fromRGBO(0xff, 0xfa, 0xf0, 1),
      border: Border.all(
        color: Color.fromRGBO(0x58, 0x50, 0x8d, 1),
        width: 3,
      ),
    );

    Widget makeBody() {
      var iconColor = Colors.black;
      var fontSize = 35.0;

      return Column(
        children: [
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 500,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: generalBoxes,
            child: new SingleChildScrollView(
              child: Column(
                children: <Widget>[
                  for (var line in recognitionOut) Container(
                    margin: EdgeInsets.fromLTRB(0, 10, 5, 0),
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    width: window.physicalSize.width,
                    height: 40 + max(1, line.length / 50 ) * 20,
                    child: Text(line),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.blueAccent),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  )
                ],
              )
            ),
          ),
          Container(
            margin: const EdgeInsets.all(3),
            padding: const EdgeInsets.all(3),
            height: 120,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: generalBoxes,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.all(20), // Set padding
                    ),
                    onPressed: getRecorderFn(),
                    child: Column(
                      children: [
                        Icon(
                          Icons.mic,
                          color: iconColor,
                          size: fontSize,
                          semanticLabel: 'modes',
                        ),
                        Text(soundRecorder!.isRecording ? 'Stop' : 'Record'),
                      ],
                    )),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.all(20), // Set padding
                    ),
                    onPressed: getPlaybackFn(),
                    child: Column(
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: iconColor,
                          size: fontSize,
                          semanticLabel: 'modes',
                        ),
                        Text(soundPlayer!.isPlaying ? 'Stop' : 'Play'),
                      ],
                    )),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.all(20), // Set padding
                  ),
                  onPressed: recognizeSound(),
                  child: Column(
                    children: [
                      Icon(
                        Icons.text_snippet_outlined,
                        color: iconColor,
                        size: fontSize,
                        semanticLabel: 'modes',
                      ),
                      Text("Recognize"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: Color.fromRGBO(0x00, 0x3F, 0x5C, 1),
      appBar: AppBar(
        title: const Center(child: Text('German ASR')),
      ),
      body: makeBody(),
    );
  }
}