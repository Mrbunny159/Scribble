import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme.dart';

class CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;
  final List<Color> recentColors;
  final ValueChanged<Color> onColorSelected;

  const CustomColorPickerDialog({
    super.key,
    required this.initialColor,
    required this.recentColors,
    required this.onColorSelected,
  });

  @override
  State<CustomColorPickerDialog> createState() => _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<CustomColorPickerDialog> {
  late HSVColor _currentHsv;

  // Curated aesthetic palettes
  static const List<Color> _vibrantPalette = [
    Color(0xFFFF1744), Color(0xFFFF5252), Color(0xFFFF5C38), Color(0xFFFF9100),
    Color(0xFFFFEA00), Color(0xFF76FF03), Color(0xFF00E676), Color(0xFF1DE9B6),
    Color(0xFF00E5FF), Color(0xFF2979FF), Color(0xFF651FFF), Color(0xFFD500F9),
    Color(0xFFF50057), Color(0xFFFFFFFF), Color(0xFF1B1C1A),
  ];

  static const List<Color> _pastelPalette = [
    Color(0xFFFFB3BA), Color(0xFFFFDFBA), Color(0xFFFFFFBA), Color(0xFFBAFFC9),
    Color(0xFFBAE1FF), Color(0xFFD7BDE2), Color(0xFFFADBD8), Color(0xFFD5F5E3),
    Color(0xFFE8DAEF), Color(0xFFFCF3CF), Color(0xFFD0ECE7), Color(0xFFFAD7A0),
  ];

  static const List<Color> _earthyPalette = [
    Color(0xFF2C3E50), Color(0xFF34495E), Color(0xFF16A085), Color(0xFF27AE60),
    Color(0xFF2980B9), Color(0xFF8E44AD), Color(0xFFF39C12), Color(0xFFD35400),
    Color(0xFFC0392B), Color(0xFF7F8C8D), Color(0xFF5D4037), Color(0xFF455A64),
  ];

  @override
  void initState() {
    super.initState();
    _currentHsv = HSVColor.fromColor(widget.initialColor);
  }

  Color get _selectedColor => _currentHsv.toColor();

  String _toHex(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _selectedColor;

    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.palette_rounded, color: AppColors.primaryContainer, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'Custom Ink Color',
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: AppColors.onSurface,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Live Color Preview Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceContainerHigh),
                ),
                child: Row(
                  children: [
                    // Color swatch circle with border
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: currentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black26, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: currentColor.withAlpha(100),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _toHex(currentColor),
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: AppColors.onSurface,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'RGB: (${currentColor.red}, ${currentColor.green}, ${currentColor.blue})',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.outline,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Interactive Saturation & Value Box
              Text(
                'Tone & Vibrancy',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onPanDown: (details) => _updateSatVal(details.localPosition, constraints.biggest),
                        onPanUpdate: (details) => _updateSatVal(details.localPosition, constraints.biggest),
                        child: Stack(
                          children: [
                            // Base hue color
                            Container(
                              color: HSVColor.fromAHSV(1.0, _currentHsv.hue, 1.0, 1.0).toColor(),
                            ),
                            // White to transparent horizontal gradient (Saturation)
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.white, Colors.transparent],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                              ),
                            ),
                            // Transparent to black vertical gradient (Value / Brightness)
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.transparent, Colors.black],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                            // Selector thumb
                            Positioned(
                              left: (_currentHsv.saturation * constraints.maxWidth).clamp(8.0, constraints.maxWidth - 8.0) - 8,
                              top: ((1.0 - _currentHsv.value) * constraints.maxHeight).clamp(8.0, constraints.maxHeight - 8.0) - 8,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: currentColor,
                                  border: Border.all(color: Colors.white, width: 2.5),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black45, blurRadius: 4),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Hue Spectrum Slider
              Text(
                'Hue Spectrum',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onPanDown: (details) => _updateHue(details.localPosition.dx, constraints.maxWidth),
                        onPanUpdate: (details) => _updateHue(details.localPosition.dx, constraints.maxWidth),
                        child: Stack(
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
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
                              ),
                            ),
                            Positioned(
                              left: ((_currentHsv.hue / 360.0) * constraints.maxWidth).clamp(7.0, constraints.maxWidth - 7.0) - 7,
                              top: 2,
                              bottom: 2,
                              child: Container(
                                width: 14,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(color: Colors.black45, width: 1.5),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black38, blurRadius: 3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Recent Colors (if any)
              if (widget.recentColors.isNotEmpty) ...[
                Text(
                  'Recently Used',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.recentColors.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final c = widget.recentColors[idx];
                      return GestureDetector(
                        onTap: () => setState(() => _currentHsv = HSVColor.fromColor(c)),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: currentColor.value == c.value ? AppColors.primaryContainer : Colors.black12,
                              width: currentColor.value == c.value ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Quick Swatches Tabs
              Text(
                'Quick Palettes',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._vibrantPalette.map((c) => _buildSwatchTile(c, currentColor)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Soft & Pastels',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._pastelPalette.map((c) => _buildSwatchTile(c, currentColor)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Deep & Earthy',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._earthyPalette.map((c) => _buildSwatchTile(c, currentColor)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryContainer,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          onPressed: () {
            widget.onColorSelected(_selectedColor);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text('Use Color', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _buildSwatchTile(Color c, Color selected) {
    final isSelected = selected.value == c.value;
    return GestureDetector(
      onTap: () => setState(() => _currentHsv = HSVColor.fromColor(c)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: c,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.black : Colors.black12,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: c.withAlpha(120), blurRadius: 6, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }

  void _updateSatVal(Offset localPosition, Size size) {
    final sat = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final val = (1.0 - (localPosition.dy / size.height)).clamp(0.0, 1.0);
    setState(() {
      _currentHsv = _currentHsv.withSaturation(sat).withValue(val);
    });
  }

  void _updateHue(double dx, double width) {
    final hue = ((dx / width) * 360.0).clamp(0.0, 360.0);
    setState(() {
      _currentHsv = _currentHsv.withHue(hue);
    });
  }
}
