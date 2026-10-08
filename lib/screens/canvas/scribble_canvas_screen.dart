import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import '../../services/firebase_service.dart';
import '../../services/image_save_service.dart';
import 'widgets/color_picker_dialog.dart';

class DrawnStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  DrawnStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });
}

class CanvasTextItem {
  String text;
  Offset position;
  Color color;
  double fontSize;
  String fontFamily;
  double rotation; // in radians
  bool isBold;
  bool isItalic;
  bool isUnderline;

  CanvasTextItem({
    required this.text,
    required this.position,
    required this.color,
    this.fontSize = 32.0,
    this.fontFamily = 'Caveat',
    this.rotation = 0.0,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
  });
}

enum DrawingTool { pen, eraser, text }

class ScribbleCanvasScreen extends StatefulWidget {
  final String connectionId;
  final String partnerName;

  const ScribbleCanvasScreen({
    super.key,
    required this.connectionId,
    required this.partnerName,
  });

  @override
  State<ScribbleCanvasScreen> createState() => _ScribbleCanvasScreenState();
}

class _ScribbleCanvasScreenState extends State<ScribbleCanvasScreen> {
  final GlobalKey _canvasKey = GlobalKey();

  // Canvas State
  final List<DrawnStroke> _strokes = [];
  final List<DrawnStroke> _redoStrokes = [];
  final List<CanvasTextItem> _textItems = [];
  final List<CanvasTextItem> _redoTextItems = [];

  DrawnStroke? _currentStroke;

  // Selected tool & styles
  DrawingTool _selectedTool = DrawingTool.pen;
  Color _selectedColor = AppColors.drawingPalette[0]; // Coral
  double _penWidth = 4.0;
  bool _isSending = false;
  bool _isSavingImage = false;

  int? _selectedTextIndex;
  String _selectedFontFamily = 'Caveat';
  bool _isTextBold = false;
  bool _isTextItalic = false;
  bool _isTextUnderline = false;

  List<Color> _recentColors = [];

  final TextEditingController _textInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecentColors();
  }

  Future<void> _loadRecentColors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('scribble_recent_colors') ?? [];
      if (list.isNotEmpty && mounted) {
        setState(() {
          _recentColors = list.map((hex) => Color(int.parse(hex))).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveRecentColor(Color color) async {
    setState(() {
      _recentColors.removeWhere((c) => c.value == color.value);
      _recentColors.insert(0, color);
      if (_recentColors.length > 8) {
        _recentColors = _recentColors.sublist(0, 8);
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final hexList = _recentColors.map((c) => c.value.toString()).toList();
      await prefs.setStringList('scribble_recent_colors', hexList);
    } catch (_) {}
  }

  void _openColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => CustomColorPickerDialog(
        initialColor: _selectedColor,
        recentColors: _recentColors,
        onColorSelected: (color) {
          setState(() {
            _selectedColor = color;
            if (_selectedTool == DrawingTool.text &&
                _selectedTextIndex != null &&
                _selectedTextIndex! < _textItems.length) {
              _textItems[_selectedTextIndex!].color = color;
            }
          });
          _saveRecentColor(color);
        },
      ),
    );
  }

  Future<void> _saveImageToDevice() async {
    if (_strokes.isEmpty && _textItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Canvas is empty. Draw or write something first!', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Deselect active text box so handles aren't captured
    if (_selectedTextIndex != null) {
      setState(() => _selectedTextIndex = null);
      await WidgetsBinding.instance.endOfFrame;
    }

    setState(() => _isSavingImage = true);

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Canvas not ready');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to generate image bytes');

      final pngBytes = byteData.buffer.asUint8List();
      final msg = await ImageSaveService.saveImageToDevice(
        bytes: pngBytes,
        customTitle: 'scribble_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    msg,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.secondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save image: $e', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingImage = false);
    }
  }

  void _onPanStart(DragDownDetails details) {
    if (_selectedTool == DrawingTool.text) {
      if (_selectedTextIndex != null) {
        setState(() => _selectedTextIndex = null);
      }
      return;
    }

    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(details.globalPosition);

    setState(() {
      _selectedTextIndex = null;
      _currentStroke = DrawnStroke(
        points: [localPosition],
        color: _selectedTool == DrawingTool.eraser ? Colors.white : _selectedColor,
        strokeWidth: _selectedTool == DrawingTool.eraser ? 28.0 : _penWidth,
        isEraser: _selectedTool == DrawingTool.eraser,
      );
      _strokes.add(_currentStroke!);
      _redoStrokes.clear();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_selectedTool == DrawingTool.text || _currentStroke == null) return;

    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPosition = box.globalToLocal(details.globalPosition);

    setState(() {
      _currentStroke!.points.add(localPosition);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _currentStroke = null;
  }

  void _undo() {
    if (_strokes.isNotEmpty) {
      setState(() {
        _redoStrokes.add(_strokes.removeLast());
      });
    } else if (_textItems.isNotEmpty) {
      setState(() {
        _redoTextItems.add(_textItems.removeLast());
      });
    }
  }

  void _redo() {
    if (_redoStrokes.isNotEmpty) {
      setState(() {
        _strokes.add(_redoStrokes.removeLast());
      });
    } else if (_redoTextItems.isNotEmpty) {
      setState(() {
        _textItems.add(_redoTextItems.removeLast());
      });
    }
  }

  void _clearCanvas() {
    if (_strokes.isEmpty && _textItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear Canvas?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: AppColors.onSurface),
        ),
        content: Text(
          'This will remove all your current drawings and text.',
          style: GoogleFonts.plusJakartaSans(color: AppColors.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              setState(() {
                _strokes.clear();
                _redoStrokes.clear();
                _textItems.clear();
                _redoTextItems.clear();
              });
              Navigator.pop(ctx);
            },
            child: Text('Clear', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  TextStyle _getTextStyle(CanvasTextItem item) {
    TextStyle base;
    switch (item.fontFamily) {
      case 'Patrick Hand':
        base = GoogleFonts.patrickHand(fontSize: item.fontSize, color: item.color);
        break;
      case 'Plus Jakarta Sans':
        base = GoogleFonts.plusJakartaSans(fontSize: item.fontSize, color: item.color);
        break;
      case 'Caveat':
      default:
        base = GoogleFonts.caveat(fontSize: item.fontSize, color: item.color);
        break;
    }
    return base.copyWith(
      fontWeight: item.isBold ? FontWeight.w900 : FontWeight.w500,
      fontStyle: item.isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: item.isUnderline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: item.color,
      decorationThickness: 2.5,
    );
  }

  TextStyle _buildSampleTextStyle(
    String font,
    double size,
    Color color, {
    bool isBold = false,
    bool isItalic = false,
    bool isUnderline = false,
  }) {
    TextStyle base;
    switch (font) {
      case 'Patrick Hand':
        base = GoogleFonts.patrickHand(fontSize: size.clamp(16, 42), color: color);
        break;
      case 'Plus Jakarta Sans':
        base = GoogleFonts.plusJakartaSans(fontSize: size.clamp(16, 42), color: color);
        break;
      case 'Caveat':
      default:
        base = GoogleFonts.caveat(fontSize: size.clamp(16, 42), color: color);
        break;
    }
    return base.copyWith(
      fontWeight: isBold ? FontWeight.w900 : FontWeight.w500,
      fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
      decoration: isUnderline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: color,
      decorationThickness: 2.0,
    );
  }

  void _showAddTextDialog({int? editIndex}) {
    final isEditing = editIndex != null && editIndex < _textItems.length;
    _textInputController.text = isEditing ? _textItems[editIndex].text : '';
    String tempFont = isEditing ? _textItems[editIndex].fontFamily : _selectedFontFamily;
    double tempSize = isEditing ? _textItems[editIndex].fontSize : 48.0;
    Color tempColor = isEditing ? _textItems[editIndex].color : _selectedColor;
    bool tempBold = isEditing ? _textItems[editIndex].isBold : _isTextBold;
    bool tempItalic = isEditing ? _textItems[editIndex].isItalic : _isTextItalic;
    bool tempUnderline = isEditing ? _textItems[editIndex].isUnderline : _isTextUnderline;
    double tempRotation = isEditing ? _textItems[editIndex].rotation : 0.0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceContainerLowest,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.text_fields_rounded, color: AppColors.primaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                isEditing ? 'Customize Text' : 'Add Text',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: AppColors.onSurface, fontSize: 18),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Text input with live formatted styling
                  TextField(
                    controller: _textInputController,
                    autofocus: true,
                    style: _buildSampleTextStyle(
                      tempFont,
                      tempSize,
                      tempColor,
                      isBold: tempBold,
                      isItalic: tempItalic,
                      isUnderline: tempUnderline,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: GoogleFonts.caveat(fontSize: 22, color: AppColors.outline),
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Formatting Row: Bold, Italic, Underline
                  Text(
                    'Formatting',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildFormatDialogButton(
                        label: 'B',
                        tooltip: 'Bold',
                        isSelected: tempBold,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        onTap: () => setDialogState(() => tempBold = !tempBold),
                      ),
                      const SizedBox(width: 8),
                      _buildFormatDialogButton(
                        label: 'I',
                        tooltip: 'Italic',
                        isSelected: tempItalic,
                        style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, fontSize: 16),
                        onTap: () => setDialogState(() => tempItalic = !tempItalic),
                      ),
                      const SizedBox(width: 8),
                      _buildFormatDialogButton(
                        label: 'U',
                        tooltip: 'Underline',
                        isSelected: tempUnderline,
                        style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700, fontSize: 16),
                        onTap: () => setDialogState(() => tempUnderline = !tempUnderline),
                      ),
                      const Spacer(),
                      // Quick Color trigger in dialog
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => CustomColorPickerDialog(
                              initialColor: tempColor,
                              recentColors: _recentColors,
                              onColorSelected: (col) {
                                setDialogState(() => tempColor = col);
                                _saveRecentColor(col);
                              },
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.surfaceContainerHigh),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: tempColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black26),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text('Color', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Font Style Selection
                  Text(
                    'Font Style',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final font in [
                        {'key': 'Caveat', 'label': '✍️ Handwritten'},
                        {'key': 'Patrick Hand', 'label': '🎨 Playful'},
                        {'key': 'Plus Jakarta Sans', 'label': '📝 Clean'},
                      ])
                        ChoiceChip(
                          label: Text(font['label']!),
                          selected: tempFont == font['key'],
                          onSelected: (val) {
                            if (val) setDialogState(() => tempFont = font['key']!);
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Font Size Slider with XXL range (16px to 150px)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Font Size',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant),
                      ),
                      Text(
                        '${tempSize.toInt()}px',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primaryContainer),
                      ),
                    ],
                  ),
                  Slider(
                    value: tempSize.clamp(16.0, 150.0),
                    min: 16.0,
                    max: 150.0,
                    activeColor: AppColors.primaryContainer,
                    onChanged: (val) => setDialogState(() => tempSize = val),
                  ),
                  // Quick Preset Chips (S, M, L, XL, XXL)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final preset in [
                        {'label': 'S (24)', 'val': 24.0},
                        {'label': 'M (48)', 'val': 48.0},
                        {'label': 'L (80)', 'val': 80.0},
                        {'label': 'XL (120)', 'val': 120.0},
                        {'label': 'XXL (150)', 'val': 150.0},
                      ])
                        GestureDetector(
                          onTap: () => setDialogState(() => tempSize = preset['val'] as double),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (tempSize - (preset['val'] as double)).abs() < 4
                                  ? AppColors.primaryContainer.withAlpha(40)
                                  : AppColors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (tempSize - (preset['val'] as double)).abs() < 4
                                    ? AppColors.primaryContainer
                                    : AppColors.surfaceContainerHigh,
                              ),
                            ),
                            child: Text(
                              preset['label'] as String,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: (tempSize - (preset['val'] as double)).abs() < 4
                                    ? AppColors.primaryContainer
                                    : AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Rotation Angle Slider (-180° to +180°)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Rotation Angle',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.onSurfaceVariant),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(tempRotation * 180 / math.pi).round()}°',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary),
                          ),
                          if (tempRotation.abs() > 0.05) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setDialogState(() => tempRotation = 0.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('0° Reset', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  Slider(
                    value: (tempRotation * 180 / math.pi).clamp(-180.0, 180.0),
                    min: -180.0,
                    max: 180.0,
                    activeColor: AppColors.secondary,
                    onChanged: (val) => setDialogState(() => tempRotation = val * math.pi / 180),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryContainer,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () {
                final text = _textInputController.text.trim();
                if (text.isNotEmpty) {
                  setState(() {
                    if (isEditing) {
                      _textItems[editIndex].text = text;
                      _textItems[editIndex].fontFamily = tempFont;
                      _textItems[editIndex].fontSize = tempSize;
                      _textItems[editIndex].color = tempColor;
                      _textItems[editIndex].isBold = tempBold;
                      _textItems[editIndex].isItalic = tempItalic;
                      _textItems[editIndex].isUnderline = tempUnderline;
                      _textItems[editIndex].rotation = tempRotation;
                    } else {
                      _textItems.add(
                        CanvasTextItem(
                          text: text,
                          position: const Offset(50, 160),
                          color: tempColor,
                          fontSize: tempSize,
                          fontFamily: tempFont,
                          isBold: tempBold,
                          isItalic: tempItalic,
                          isUnderline: tempUnderline,
                          rotation: tempRotation,
                        ),
                      );
                      _selectedTextIndex = _textItems.length - 1;
                      _redoTextItems.clear();
                    }
                    _selectedTool = DrawingTool.text;
                    _selectedFontFamily = tempFont;
                    _isTextBold = tempBold;
                    _isTextItalic = tempItalic;
                    _isTextUnderline = tempUnderline;
                  });
                }
                Navigator.pop(ctx);
              },
              child: Text(
                isEditing ? 'Save' : 'Add Text',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatDialogButton({
    required String label,
    required String tooltip,
    required bool isSelected,
    required TextStyle style,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 38,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: style.copyWith(
                color: isSelected ? Colors.white : AppColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendScribble() async {
    if (_strokes.isEmpty && _textItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Draw something before sending!', style: GoogleFonts.plusJakartaSans()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Deselect any active text box before rasterizing canvas
    if (_selectedTextIndex != null) {
      setState(() => _selectedTextIndex = null);
      await WidgetsBinding.instance.endOfFrame;
    }

    setState(() => _isSending = true);

    try {
      final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Canvas not ready');

      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to generate image');

      final pngBytes = byteData.buffer.asUint8List();

      await FirebaseService().sendScribble(
        connectionId: widget.connectionId,
        pngBytes: pngBytes,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scribble sent to ${widget.partnerName}! Updating lock screen...',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.primaryContainer,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send scribble: $e', style: GoogleFonts.plusJakartaSans()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scribble for ${widget.partnerName}',
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Appears on their lock screen in real time',
              style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: AppColors.primary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            onPressed: (_strokes.isNotEmpty || _textItems.isNotEmpty) ? _undo : null,
            tooltip: 'Undo',
          ),
          IconButton(
            icon: const Icon(Icons.redo_rounded),
            onPressed: (_redoStrokes.isNotEmpty || _redoTextItems.isNotEmpty) ? _redo : null,
            tooltip: 'Redo',
          ),
          IconButton(
            icon: _isSavingImage
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            onPressed: (_strokes.isNotEmpty || _textItems.isNotEmpty) && !_isSavingImage ? _saveImageToDevice : null,
            tooltip: 'Save Image to Device',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
            onPressed: _clearCanvas,
            tooltip: 'Clear Canvas',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: Stack(
                    children: [
                      // The entire canvas including lines, strokes, and text items is inside RepaintBoundary!
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () {
                            if (_selectedTextIndex != null) {
                              setState(() => _selectedTextIndex = null);
                            }
                          },
                          onPanDown: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          child: RepaintBoundary(
                            key: _canvasKey,
                            child: Container(
                              color: Colors.white,
                              child: Stack(
                                children: [
                                  // Ruled Notebook Lines
                                  Positioned.fill(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                      children: List.generate(
                                        18,
                                        (_) => Container(
                                          height: 1,
                                          color: AppColors.outlineVariant.withAlpha(50),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // Custom Paint for strokes
                                  CustomPaint(
                                    painter: _ScribblePainter(
                                      strokes: _strokes,
                                    ),
                                    child: Container(),
                                  ),
                                  // Floating Draggable, Resizable & Customizable Text Labels
                                  for (int i = 0; i < _textItems.length; i++)
                                    _buildCanvasTextWidget(i),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomStudio(),
            ],
          ),

          // Loading Overlay
          if (_isSending)
            Positioned.fill(
              child: Container(
                color: Colors.black.withAlpha(120),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      Text(
                        'Sending to Lock Screen...',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCanvasTextWidget(int i) {
    final item = _textItems[i];
    final isSelected = _selectedTextIndex == i;

    return Positioned(
      left: item.position.dx,
      top: item.position.dy,
      child: Transform.rotate(
        angle: item.rotation,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedTextIndex = i;
              _selectedTool = DrawingTool.text;
              _selectedColor = item.color;
              _selectedFontFamily = item.fontFamily;
              _isTextBold = item.isBold;
              _isTextItalic = item.isItalic;
              _isTextUnderline = item.isUnderline;
            });
          },
          onDoubleTap: () => _showAddTextDialog(editIndex: i),
          onPanUpdate: (details) {
            setState(() {
              item.position += details.delta;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: AppColors.primaryContainer, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
              borderRadius: BorderRadius.circular(10),
              color: isSelected ? Colors.white.withAlpha(210) : Colors.transparent,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.text,
                  style: _getTextStyle(item),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  // Edit Button
                  GestureDetector(
                    onTap: () => _showAddTextDialog(editIndex: i),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryFixed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_rounded, size: 13, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Rotate Handle (interactive drag to rotate)
                  GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        item.rotation += details.delta.dx * 0.03;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryFixed,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.rotate_right_rounded, size: 13, color: AppColors.secondary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Delete Button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _redoTextItems.add(_textItems.removeAt(i));
                        _selectedTextIndex = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomStudio() {
    final hasSelectedText = _selectedTool == DrawingTool.text &&
        _selectedTextIndex != null &&
        _selectedTextIndex! < _textItems.length;
    final selectedText = hasSelectedText ? _textItems[_selectedTextIndex!] : null;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: const Border(
          top: BorderSide(color: AppColors.surfaceContainerHigh, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: Tools & Sizes / Text Customization Controls
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildToolButton(
                    icon: Icons.edit_rounded,
                    label: 'Pen',
                    tool: DrawingTool.pen,
                  ),
                  const SizedBox(width: 8),
                  _buildToolButton(
                    icon: Icons.auto_fix_normal_rounded,
                    label: 'Eraser',
                    tool: DrawingTool.eraser,
                  ),
                  const SizedBox(width: 8),
                  _buildToolButton(
                    icon: Icons.text_fields_rounded,
                    label: 'Text',
                    tool: DrawingTool.text,
                    onTap: () {
                      setState(() => _selectedTool = DrawingTool.text);
                      if (_textItems.isEmpty || _selectedTextIndex == null) {
                        _showAddTextDialog();
                      }
                    },
                  ),
                  const SizedBox(width: 14),

                  // Pen Stroke Width Presets
                  if (_selectedTool == DrawingTool.pen) ...[
                    for (final size in [2.0, 4.0, 8.0, 14.0])
                      GestureDetector(
                        onTap: () => setState(() => _penWidth = size),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _penWidth == size
                                ? AppColors.primaryContainer.withAlpha(50)
                                : Colors.transparent,
                            border: Border.all(
                              color: _penWidth == size ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Container(
                              width: size + 2,
                              height: size + 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _selectedColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],

                  // Text Formatting, Resizing, Rotation & Font Customization Toolbar
                  if (_selectedTool == DrawingTool.text) ...[
                    if (selectedText != null) ...[
                      // Font family selector chips
                      for (final font in [
                        {'key': 'Caveat', 'label': '✍️ Caveat'},
                        {'key': 'Patrick Hand', 'label': '🎨 Playful'},
                        {'key': 'Plus Jakarta Sans', 'label': '📝 Sans'},
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(font['label']!, style: const TextStyle(fontSize: 11)),
                            selected: selectedText.fontFamily == font['key'],
                            onSelected: (val) {
                              if (val) {
                                setState(() {
                                  selectedText.fontFamily = font['key']!;
                                  _selectedFontFamily = font['key']!;
                                });
                              }
                            },
                          ),
                        ),
                      const SizedBox(width: 4),

                      // Text Formatting Toggles: B, I, U
                      _buildToolbarFormatButton(
                        label: 'B',
                        isSelected: selectedText.isBold,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                        onTap: () {
                          setState(() {
                            selectedText.isBold = !selectedText.isBold;
                            _isTextBold = selectedText.isBold;
                          });
                        },
                      ),
                      _buildToolbarFormatButton(
                        label: 'I',
                        isSelected: selectedText.isItalic,
                        style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700),
                        onTap: () {
                          setState(() {
                            selectedText.isItalic = !selectedText.isItalic;
                            _isTextItalic = selectedText.isItalic;
                          });
                        },
                      ),
                      _buildToolbarFormatButton(
                        label: 'U',
                        isSelected: selectedText.isUnderline,
                        style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w700),
                        onTap: () {
                          setState(() {
                            selectedText.isUnderline = !selectedText.isUnderline;
                            _isTextUnderline = selectedText.isUnderline;
                          });
                        },
                      ),
                      const SizedBox(width: 6),

                      // Text Size slider & indicator (up to 150px)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${selectedText.fontSize.toInt()}px',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryContainer),
                          ),
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: selectedText.fontSize.clamp(16.0, 150.0),
                              min: 16.0,
                              max: 150.0,
                              activeColor: AppColors.primaryContainer,
                              onChanged: (val) {
                                setState(() => selectedText.fontSize = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),

                      // Text Rotation Slider & Reset
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(selectedText.rotation * 180 / math.pi).round()}°',
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.secondary),
                          ),
                          SizedBox(
                            width: 80,
                            child: Slider(
                              value: (selectedText.rotation * 180 / math.pi).clamp(-180.0, 180.0),
                              min: -180.0,
                              max: 180.0,
                              activeColor: AppColors.secondary,
                              onChanged: (val) {
                                setState(() => selectedText.rotation = val * math.pi / 180);
                              },
                            ),
                          ),
                          if (selectedText.rotation.abs() > 0.05)
                            GestureDetector(
                              onTap: () => setState(() => selectedText.rotation = 0.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('0°', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),

                      // Edit and New text buttons
                      IconButton(
                        icon: const Icon(Icons.edit_note_rounded, size: 20, color: AppColors.primary),
                        tooltip: 'Edit text in modal',
                        onPressed: () => _showAddTextDialog(editIndex: _selectedTextIndex),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_rounded, size: 20, color: AppColors.primaryContainer),
                        tooltip: 'Add another text',
                        onPressed: () => _showAddTextDialog(),
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: () => _showAddTextDialog(),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add Text Message'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryContainer,
                          side: const BorderSide(color: AppColors.primaryContainer),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Row 2: Inks Palette, Recent Colors, Custom Color Picker & Send Button
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      children: [
                        // Custom Color Picker Button
                        GestureDetector(
                          onTap: _openColorPicker,
                          child: Tooltip(
                            message: 'Pick any custom color',
                            child: Container(
                              margin: const EdgeInsets.only(right: 10),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const SweepGradient(
                                  colors: [
                                    Color(0xFFFF0000),
                                    Color(0xFFFFFF00),
                                    Color(0xFF00FF00),
                                    Color(0xFF00FFFF),
                                    Color(0xFF0000FF),
                                    Color(0xFFFF00FF),
                                    Color(0xFFFF0000),
                                  ],
                                ),
                                border: Border.all(color: Colors.white, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 1)),
                                ],
                              ),
                              child: const Center(
                                child: Icon(Icons.colorize_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ),

                        // Recent Colors Swatches (if any)
                        if (_recentColors.isNotEmpty) ...[
                          for (final color in _recentColors)
                            _buildColorSwatch(
                              color: color,
                              isSelected: _selectedColor.value == color.value,
                              selectedText: selectedText,
                              isRecent: true,
                            ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            width: 1.5,
                            color: AppColors.surfaceContainerHigh,
                          ),
                        ],

                        // Standard Palette Colors
                        for (final color in AppColors.drawingPalette)
                          _buildColorSwatch(
                            color: color,
                            isSelected: _selectedColor.value == color.value,
                            selectedText: selectedText,
                            isRecent: false,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendScribble,
                  icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
                  label: Text(
                    'Send',
                    style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required DrawingTool tool,
    VoidCallback? onTap,
  }) {
    final isSelected = _selectedTool == tool;
    return InkWell(
      onTap: onTap ?? () => setState(() => _selectedTool = tool),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryFixed : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSwatch({
    required Color color,
    required bool isSelected,
    required CanvasTextItem? selectedText,
    required bool isRecent,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
          if (_selectedTool == DrawingTool.text && selectedText != null) {
            selectedText.color = color;
          }
        });
        _saveRecentColor(color);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: isSelected ? 36 : 28,
          height: isSelected ? 36 : 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.black : Colors.black12,
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withAlpha(120),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: isRecent && !isSelected
              ? Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color.computeLuminance() > 0.5 ? Colors.black45 : Colors.white70,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildToolbarFormatButton({
    required String label,
    required bool isSelected,
    required TextStyle style,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.only(right: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
            width: 1.2,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: style.copyWith(
              color: isSelected ? Colors.white : AppColors.onSurface,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScribblePainter extends CustomPainter {
  final List<DrawnStroke> strokes;

  _ScribblePainter({
    required this.strokes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke.strokeWidth
        ..style = PaintingStyle.stroke;

      if (stroke.points.isEmpty) continue;

      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.strokeWidth / 2, paint..style = PaintingStyle.fill);
        continue;
      }

      final path = Path();
      path.moveTo(stroke.points.first.dx, stroke.points.first.dy);

      for (int i = 1; i < stroke.points.length; i++) {
        final p0 = stroke.points[i - 1];
        final p1 = stroke.points[i];
        final midPoint = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
        path.quadraticBezierTo(p0.dx, p0.dy, midPoint.dx, midPoint.dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScribblePainter oldDelegate) => true;
}
