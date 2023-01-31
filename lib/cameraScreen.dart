import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../main.dart';

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {

  CameraController? controller;
  bool _isCameraInitialized = false;
  final resolutionPresets = ResolutionPreset.values;
  ResolutionPreset currentResolutionPreset = ResolutionPreset.high;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 10.0;
  double _currentZoomLevel = 1.0;

  double _minAvailableExposureOffset = -4.0;
  double _maxAvailableExposureOffset = 4.0;
  double _currentExposureOffset = 0.0;

  FlashMode? _currentFlashMode;

  bool _isRearCameraSelected = true;

  bool _isVideoCameraSelected = false;
  bool _isRecordingInProgress = false;

  VideoPlayerController? videoController;
  File? _imageFile;
  File? _videoFile;
  List<File> allFileList = [];

  refreshAlreadyCapturedImages() async {
    final directory = await getApplicationDocumentsDirectory();
    List<FileSystemEntity> fileList = await directory.list().toList();
    allFileList.clear();
    List<Map<int, dynamic>> fileNames = [];

    fileList.forEach((file) {
      if (file.path.contains('.jpg') || file.path.contains('.mp4')) {
        allFileList.add(File(file.path));

        String name = file.path.split('/').last.split('.').first;
        fileNames.add({0: int.parse(name), 1: file.path.split('/').last});
      }
    });

    if (fileNames.isNotEmpty) {
      final recentFile =
      fileNames.reduce((curr, next) => curr[0] > next[0] ? curr : next);
      String recentFileName = recentFile[1];
      if (recentFileName.contains('.mp4')) {
        _videoFile = File('${directory.path}/$recentFileName');
        _imageFile = null;
        _startVideoPlayer();
      } else {
        _imageFile = File('${directory.path}/$recentFileName');
        _videoFile = null;
      }

      setState(() {});
    }
  }

  Future<void> _startVideoPlayer() async {
    if (_videoFile != null) {
      videoController = VideoPlayerController.file(_videoFile!);
      await videoController!.initialize().then((_) {
        // Ensure the first frame is shown after the video is initialized,
        // even before the play button has been pressed.
        setState(() {});
      });
      await videoController!.setLooping(true);
      await videoController!.play();
    }
  }

  Future<void> startVideoRecording() async {
    final CameraController? cameraController = controller;

    if (controller!.value.isRecordingVideo) {
      // A recording has already started, do nothing.
      return;
    }

    try {
      await cameraController!.startVideoRecording();
      setState(() {
        _isRecordingInProgress = true;
        debugPrint(_isRecordingInProgress.toString());
      });
    } on CameraException catch (e) {
      print('Error starting to record video: $e');
    }
  }


  Future<XFile?> stopVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // Recording is already is stopped state
      return null;
    }

    try {
      XFile file = await controller!.stopVideoRecording();
      setState(() {
        _isRecordingInProgress = false;
      });
      return file;
    } on CameraException catch (e) {
      print('Error stopping video recording: $e');
      return null;
    }
  }

  Future<void> pauseVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // Video recording is not in progress
      return;
    }

    try {
      await controller!.pauseVideoRecording();
    } on CameraException catch (e) {
      debugPrint('Error pausing video recording: $e');
    }
  }

  Future<void> resumeVideoRecording() async {
    if (!controller!.value.isRecordingVideo) {
      // No video recording was in progress
      return;
    }

    try {
      await controller!.resumeVideoRecording();
    } on CameraException catch (e) {
      debugPrint('Error resuming video recording: $e');
    }
  }


  Future<XFile?> takePicture() async {
    final CameraController? cameraController = controller;

    if (cameraController!.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      XFile file = await cameraController.takePicture();
      return file;
    } on CameraException catch (e) {
      debugPrint('Error occured while taking picture: $e');
      return null;
    }
  }
  void onNewCameraSelected(CameraDescription cameraDescription) async {
    final previousCameraController = controller;
    // Instantiating the camera controller
    final CameraController cameraController = CameraController(
      cameraDescription,
      currentResolutionPreset,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    // Dispose the previous controller
    await previousCameraController?.dispose();

    // Replace with the new controller
    if (mounted) {
      setState(() {
        controller = cameraController;
      });
    }

    // Update UI if controller updated
    cameraController.addListener(() {
      if (mounted) setState(() {});
    });

    // Initialize controller
    try {
      await cameraController.initialize();
      await Future.wait([
        cameraController
            .getMinExposureOffset()
            .then((value) => _minAvailableExposureOffset = value),
        cameraController
            .getMaxExposureOffset()
            .then((value) => _maxAvailableExposureOffset = value),
        cameraController
            .getMaxZoomLevel()
            .then((value) => _maxAvailableZoom = value),
        cameraController
            .getMinZoomLevel()
            .then((value) => _minAvailableZoom = value),
      ]);

      _currentFlashMode = controller!.value.flashMode;
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
    }
    try {
      await cameraController.initialize();
    } on CameraException catch (e) {
      print('Error initializing camera: $e');
    }

    // Update the Boolean
    if (mounted) {
      setState(() {
        _isCameraInitialized = controller!.value.isInitialized;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = controller;

    // App state changed before we got the chance to initialize.
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // Free up memory when camera not active
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize the camera with same properties
      onNewCameraSelected(cameraController.description);
    }
    // TODO: implement didChangeAppLifecycleState
    super.didChangeAppLifecycleState(state);
  }

  @override
  void initState() {
    SystemChrome.setEnabledSystemUIOverlays([]);
    onNewCameraSelected(cameras[0]);
    super.initState();
  }

  @override
  void dispose() {
    controller?.dispose();
    videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isCameraInitialized
          ? Column(children: [
              AspectRatio(
                aspectRatio: 1 / controller!.value.aspectRatio,
                child: Stack(
                  children: [
                    controller!.buildPreview(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        16.0,
                        8.0,
                        16.0,
                        8.0,
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: 8.0,
                                    right: 8.0,
                                  ),
                                  child: DropdownButton<ResolutionPreset>(
                                    dropdownColor: Colors.black87,
                                    underline: Container(),
                                    value: currentResolutionPreset,
                                    items: [
                                      for (ResolutionPreset preset
                                          in resolutionPresets)
                                        DropdownMenuItem(
                                          value: preset,
                                          child: Text(
                                            preset
                                                .toString()
                                                .split('.')[1]
                                                .toUpperCase(),
                                            style: const TextStyle(
                                                color: Colors.white),
                                          ),
                                        )
                                    ],
                                    onChanged: (value) {
                                      setState(() {
                                        currentResolutionPreset = value!;
                                        _isCameraInitialized = false;
                                      });
                                      onNewCameraSelected(
                                          controller!.description);
                                    },
                                    hint: const Text("Select item"),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.only(right: 8.0, top: 16.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10.0),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    '${_currentExposureOffset.toStringAsFixed(1)}x',
                                    style: const TextStyle(color: Colors.black),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Container(
                                  height: 30,
                                  child: Slider(
                                    value: _currentExposureOffset,
                                    min: _minAvailableExposureOffset,
                                    max: _maxAvailableExposureOffset,
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white30,
                                    onChanged: (value) async {
                                      setState(() {
                                        _currentExposureOffset = value;
                                      });
                                      await controller!
                                          .setExposureOffset(value);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Slider(
                                    value: _currentZoomLevel,
                                    min: _minAvailableZoom,
                                    max: _maxAvailableZoom,
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white30,
                                    onChanged: (value) async {
                                      setState(() {
                                        _currentZoomLevel = value;
                                      });
                                      await controller!.setZoomLevel(value);
                                    },
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(10.0),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      '${_currentZoomLevel.toStringAsFixed(1)}x',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isCameraInitialized = false;
                                    });
                                    onNewCameraSelected(
                                      cameras[_isRearCameraSelected ? 0 : 1],
                                    );
                                    setState(() {
                                      _isRearCameraSelected =
                                          !_isRearCameraSelected;
                                    });
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const Icon(
                                        Icons.circle,
                                        color: Colors.black38,
                                        size: 60,
                                      ),
                                      Icon(
                                        _isRearCameraSelected
                                            ? Icons.camera_front
                                            : Icons.camera_rear,
                                        color: Colors.white,
                                        size: 30,
                                      ),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: _isVideoCameraSelected
                                      ? () async {
                                    if (_isRecordingInProgress) {
                                      XFile? rawVideo =
                                      await stopVideoRecording();
                                      File videoFile =
                                      File(rawVideo!.path);

                                      int currentUnix = DateTime
                                          .now()
                                          .millisecondsSinceEpoch;

                                      final directory =
                                      await getApplicationDocumentsDirectory();

                                      String fileFormat = videoFile
                                          .path
                                          .split('.')
                                          .last;

                                      _videoFile =
                                      await videoFile.copy(
                                        '${directory.path}/$currentUnix.$fileFormat',
                                      );

                                      _startVideoPlayer();
                                    } else {
                                      await startVideoRecording();
                                    }
                                  }
                                      : () async {
                                    XFile? rawImage =
                                    await takePicture();
                                    File imageFile =
                                    File(rawImage!.path);

                                    int currentUnix = DateTime.now()
                                        .millisecondsSinceEpoch;

                                    final directory =
                                    await getApplicationDocumentsDirectory();
                                    String fileFormat = imageFile
                                        .path
                                        .split('.')
                                        .last;
                                    print("This is formt Picture $fileFormat");

                                    await imageFile.copy(
                                      '${directory.path}/$currentUnix.jpeg',
                                    );
                                    print("This is formt Picture after copy");

                                    refreshAlreadyCapturedImages();
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        color: _isVideoCameraSelected
                                            ? Colors.white
                                            : Colors.white38,
                                        size: 80,
                                      ),
                                      Icon(
                                        Icons.circle,
                                        color: _isVideoCameraSelected
                                            ? Colors.red
                                            : Colors.white,
                                        size: 65,
                                      ),
                                      _isVideoCameraSelected &&
                                          _isRecordingInProgress
                                          ? Icon(
                                        Icons.stop_rounded,
                                        color: Colors.white,
                                        size: 32,
                                      )
                                          : Container(),
                                    ],
                                  ),
                                ),
                                InkWell(
                                  onTap: () async {

                                    XFile? rawImage = await takePicture();
                                    File imageFile = File(rawImage!.path);

                                    int currentUnix =
                                        DateTime.now().millisecondsSinceEpoch;
                                    final directory =
                                        await getApplicationDocumentsDirectory();
                                    String fileFormat =
                                        imageFile.path.split('.').last;

                                    await imageFile.copy(
                                      '${directory.path}/$currentUnix.jpeg',

                                    );
                                    debugPrint(imageFile.path);
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: const [
                                      Icon(Icons.circle,
                                          color: Colors.white38, size: 80),
                                      Icon(Icons.circle,
                                          color: Colors.white, size: 65),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          ]),
                    ),
                  ],
                ),
              ),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 8.0,
                  right: 4.0,
                ),
                child: TextButton(
                  onPressed: _isRecordingInProgress
                      ? null
                      : () {
                    if (_isVideoCameraSelected) {
                      setState(() {
                        _isVideoCameraSelected = false;
                      });
                    }
                  },
                  style: TextButton.styleFrom(
                    primary: _isVideoCameraSelected
                        ? Colors.black54
                        : Colors.black,
                    backgroundColor: _isVideoCameraSelected
                        ? Colors.white30
                        : Colors.white,
                  ),
                  child: Text('IMAGE'),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                    left: 4.0, right: 8.0),
                child: TextButton(
                  onPressed: () {
                    if (!_isVideoCameraSelected) {
                      setState(() {
                        _isVideoCameraSelected = true;
                      });
                    }
                  },
                  style: TextButton.styleFrom(
                    primary: _isVideoCameraSelected
                        ? Colors.black
                        : Colors.black54,
                    backgroundColor: _isVideoCameraSelected
                        ? Colors.white
                        : Colors.white30,
                  ),
                  child: Text('VIDEO'),
                ),
              ),
            ),
          ],
        ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  InkWell(
                    onTap: () async {
                      setState(() {
                        _currentFlashMode = FlashMode.off;
                      });
                      await controller!.setFlashMode(
                        FlashMode.off,
                      );
                    },
                    child: Icon(
                      Icons.flash_off,
                      color: _currentFlashMode == FlashMode.off
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      setState(() {
                        _currentFlashMode = FlashMode.auto;
                      });
                      await controller!.setFlashMode(
                        FlashMode.auto,
                      );
                    },
                    child: Icon(
                      Icons.flash_auto,
                      color: _currentFlashMode == FlashMode.auto
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      setState(() {
                        _currentFlashMode = FlashMode.always;
                      });
                      await controller!.setFlashMode(
                        FlashMode.always,
                      );
                    },
                    child: Icon(
                      Icons.flash_on,
                      color: _currentFlashMode == FlashMode.always
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                  InkWell(
                    onTap: () async {
                      setState(() {
                        _currentFlashMode = FlashMode.torch;
                      });
                      await controller!.setFlashMode(
                        FlashMode.torch,
                      );
                    },
                    child: Icon(
                      Icons.highlight,
                      color: _currentFlashMode == FlashMode.torch
                          ? Colors.amber
                          : Colors.white,
                    ),
                  ),
                ],
              )
            ])
          : Container(),
    );
  }
}
