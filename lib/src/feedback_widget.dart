library feeback;

import 'package:feedback/src/better_feedback.dart';
import 'package:feedback/src/controls_column.dart';
import 'package:feedback/src/feedback_functions.dart';
import 'package:feedback/src/paint_on_background.dart';
import 'package:feedback/src/painter.dart';
import 'package:feedback/src/scale_and_clip.dart';
import 'package:feedback/src/screenshot.dart';
import 'package:feedback/src/translation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class FeedbackWidget extends StatefulWidget {
  const FeedbackWidget({
    Key key,
    @required this.child,
    @required this.feedback,
    @required this.isFeedbackVisible,
    @required this.translation,
    this.backgroundColor,
    this.drawColors,
  })  : assert(child != null),
        assert(feedback != null),
        assert(isFeedbackVisible != null),
        assert(translation != null),
        // if the user chooses to supply custom drawing colors,
        // make sure there is at least on color to draw with
        assert(
          // ignore: prefer_is_empty
          drawColors == null || (drawColors != null && drawColors.length > 0),
          'There must be at least one color to draw',
        ),
        super(key: key);

  final bool isFeedbackVisible;
  final OnFeedbackCallback feedback;
  final Widget child;
  final Color backgroundColor;
  final List<Color> drawColors;
  final FeedbackTranslation translation;

  @override
  _FeedbackWidgetState createState() => _FeedbackWidgetState();
}

class _FeedbackWidgetState extends State<FeedbackWidget>
    with SingleTickerProviderStateMixin {
  PainterController painterController;
  ScreenshotController screenshotController = ScreenshotController();
  TextEditingController textEditingController = TextEditingController();

  bool isNavigatingActive = true;
  AnimationController _controller;
  List<Color> drawColors;

  PainterController create() {
    final PainterController controller = PainterController();
    controller.thickness = 5.0;
    controller.drawColor = drawColors[0];
    return controller;
  }

  @override
  void initState() {
    super.initState();

    drawColors = widget.drawColors ??
        [
          Colors.red,
          Colors.green,
          Colors.blue,
          Colors.yellow,
        ];

    painterController = create();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
  }

  @override
  void didUpdateWidget(FeedbackWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFeedbackVisible != widget.isFeedbackVisible &&
        oldWidget.isFeedbackVisible == false) {
      // Feedback is now visible,
      // start animation to show it.
      _controller.forward();
    }

    if (oldWidget.isFeedbackVisible != widget.isFeedbackVisible &&
        oldWidget.isFeedbackVisible == true) {
      // Feedback is no longer visible,
      // reverse animation to hide it.
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.child.key is GlobalKey,
      'The child needs a GlobalKey,'
      ' so that the app doesn\'t loose its state while switching '
      'between normal use and feedback view.',
    );

    // Possible optimization:
    // If feedback is invisible just build widget.child
    // without the whole feedback foo.
    //if (!widget.isFeedbackVisible) {
    //  return widget.child;
    //}

    final scaleAnimation = Tween<double>(begin: 1, end: 0.65)
        .chain(CurveTween(curve: Curves.easeInSine))
        .animate(_controller);

    final animation = Tween<double>(begin: 0, end: 1)
        .chain(CurveTween(curve: Curves.easeInSine))
        .animate(_controller);

    final controlsHorizontalAlignment = Tween<double>(begin: 1.4, end: .95)
        .chain(CurveTween(curve: Curves.easeInSine))
        .animate(_controller);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          color: widget.backgroundColor ?? Colors.grey,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Align(
                alignment: Alignment.topCenter,
                child: ScaleAndClip(
                  scale: scaleAnimation.value,
                  alignmentProgress: animation.value,
                  child: Screenshot(
                    controller: screenshotController,
                    child: PaintOnBackground(
                      controller: painterController,
                      isPaintingActive:
                          !isNavigatingActive && widget.isFeedbackVisible,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment(
                  controlsHorizontalAlignment.value,
                  -0.7,
                ),
                child: ControlsColumn(
                  colors: drawColors,
                  onColorChanged: (color) {
                    painterController.drawColor = color;
                    _hideKeyboard(context);
                  },
                  onUndo: () {
                    painterController.undo();
                    _hideKeyboard(context);
                  },
                  onClearDrawing: () {
                    painterController.clear();
                    _hideKeyboard(context);
                  },
                  onModeChanged: (isDrawingActive) {
                    setState(() {
                      isNavigatingActive = isDrawingActive;
                      _hideKeyboard(context);
                    });
                  },
                  onCloseFeedback: () {
                    _hideKeyboard(context);
                    BetterFeedback.of(context).hide();
                  },
                ),
              ),
              if (widget.isFeedbackVisible)
                Positioned(
                  left: 0,
                  // Make sure the input field is always visible,
                  // especially if the keyboard is shown
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                  right: 0,
                  child: Material(
                    child: Container(
                      padding: const EdgeInsets.all(30),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          Text(
                            widget.translation.feedbackDescriptionText,
                            maxLines: 2,
                          ),
                          TextField(
                            maxLines: 2,
                            minLines: 2,
                            controller: textEditingController,
                          ),
                          Builder(
                            builder: (innerContext) {
                              // Through using a Builder we can supply an
                              // appropriate BuildContext to the callback
                              // function.
                              return FlatButton(
                                child: Text(
                                  widget.translation.submitButtonText,
                                ),
                                onPressed: () {
                                  sendFeedback(innerContext);
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> sendFeedback(BuildContext context) async {
    _hideKeyboard(context);

    // Wait for the keyboard to be closed, and then proceed
    // to take a screenshot
    await Future.delayed(const Duration(milliseconds: 200), () async {
      // Take high resolution screenshot
      final screenshot = await screenshotController.capture(pixelRatio: 3);

      // Get feedback text
      final feedbackText = textEditingController.text;

      // Give it to the developer
      // to do something with it.
      widget.feedback(
        context,
        feedbackText,
        screenshot,
      );
    });
  }

  void _hideKeyboard(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());
  }
}
