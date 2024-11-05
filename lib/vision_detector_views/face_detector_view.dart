import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:audioplayers/audioplayers.dart';

import 'detector_view.dart';
import 'painters/face_detector_painter.dart';

class FaceDetectorView extends StatefulWidget {
  const FaceDetectorView({
    Key? key,
    required this.drowsinessFrameThreshold,
  }) : super(key: key);
  final int drowsinessFrameThreshold;
  @override
  State<FaceDetectorView> createState() => _FaceDetectorViewState();
}

class _FaceDetectorViewState extends State<FaceDetectorView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
    ),
  );
  final AudioPlayer _audioPlayer = AudioPlayer();
  final double _closedEyeThreshold =
      0.5; // 눈 개페율. 해당값 미만이면 감긴 것으로 판단. 여기서 개인마다 값을 구할수 있을듯
  int _closedEyeFrameCount = 0;
  //final int _drowsinessFrameThreshold = 8; // ex) = 15  15프레임동안 눈 감긴상태가 지속되야 판단
  double? _leftEyeOpenProb;
  double? _rightEyeOpenProb;
  bool _isAlarmPlaying = false;

  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  String? _text;
  var _cameraLensDirection = CameraLensDirection.front;

  @override
  void dispose() {
    _canProcess = false; //이미지 처리를 중지
    _faceDetector.close();
    _audioPlayer.dispose(); // AudioPlayer 자원 해제
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DetectorView(
          title: 'Face Detector',
          customPaint: _customPaint,
          text: _text,
          onImage: _processImage,
          initialCameraLensDirection: _cameraLensDirection,
          onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
        ),
        Positioned(
          top: 50,
          left: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),
              Text(
                'Left Eye Open Probability: ${_leftEyeOpenProb?.toStringAsFixed(2) ?? 'N/A'}',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              Text(
                'Right Eye Open Probability: ${_rightEyeOpenProb?.toStringAsFixed(2) ?? 'N/A'}',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              Text(
                '_drowsinessFrameThreshold: ${widget.drowsinessFrameThreshold}',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess) return; // 이미지 처리 할 수 있는지
    if (_isBusy) return; // 현재 이미지 처리중인지
    _isBusy = true; // 이제부터 이미지 처리 할꺼임
    setState(() {
      _text = '';
    });

    final faces = await _faceDetector.processImage(inputImage); //얼굴인식, 졸음 감지 로직
    if (faces.isNotEmpty) {
      final face = faces.first;

      final double? leftEyeOpenProbability = face.leftEyeOpenProbability;
      final double? rightEyeOpenProbability = face.rightEyeOpenProbability;

      if (leftEyeOpenProbability != null && rightEyeOpenProbability != null) {
        _detectDrowsiness(leftEyeOpenProbability, rightEyeOpenProbability);
      }
    } else {
      // 얼굴이 감지되지 않으면 알람 중지
      _stopAlarm();
    }

    if (inputImage.metadata?.size !=
            null && // 이미지를 화면에 올바르게 표시하기 위한 size와 rotation이 존재하는지 확인
        inputImage.metadata?.rotation != null) {
      final painter = FaceDetectorPainter(
        // 얼굴 윤곽, 경계상자를그림
        faces, //인식된 얼굴 리스트
        inputImage.metadata!.size, //이미지 크기
        inputImage.metadata!.rotation, //이미지 회전정보
        _cameraLensDirection, //카메라 렌즈 방향
      );
      _customPaint = CustomPaint(painter: painter);
    } else {
      //얼굴인식 안되면 안그림
      // String text = 'Faces found: ${faces.length}\n\n';
      // for (final face in faces) {
      //   text += 'face: ${face.boundingBox}\n\n';
      // }
      // _text = text;

      // _customPaint = null;
    }
    _isBusy = false; //이미지 처리 완료
    if (mounted) {
      //해당 위젯이 여전히 활성화 되어있는지 확인
      setState(() {
        _text = 'Faces found: ${faces.length}\n';
      });
    }
  }

  void _detectDrowsiness(double leftEyeOpenProb, double rightEyeOpenProb) {
    if (mounted) {
      setState(() {
        _leftEyeOpenProb = leftEyeOpenProb;
        _rightEyeOpenProb = rightEyeOpenProb;
      });
    }
    if (leftEyeOpenProb < _closedEyeThreshold &&
        rightEyeOpenProb < _closedEyeThreshold) {
      _closedEyeFrameCount++;
      if (_closedEyeFrameCount >= widget.drowsinessFrameThreshold) {
        // 졸음 감지 - 알람 재생
        _triggerAlarm();
        _closedEyeFrameCount = 0;
      }
    } else {
      _closedEyeFrameCount = 0;
      _stopAlarm(); // 눈을 뜬 상태이면 알람 중지
    }
  }

  void _triggerAlarm() async {
    // 눈 감기면 호출
    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;
      await _audioPlayer.play(AssetSource('alarm.wav'));
    }
  }

  void _stopAlarm() async {
    // 눈 떠지면 호출
    if (_isAlarmPlaying) {
      await _audioPlayer.stop();
      _isAlarmPlaying = false;
    }
  }
}
