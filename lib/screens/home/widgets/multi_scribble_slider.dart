import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme.dart';
import '../../../models/scribble_model.dart';

class MultiScribbleSlider extends StatefulWidget {
  final List<ScribbleItem> items;
  final String partnerName;
  final String connectionId;
  final VoidCallback onDoubleTap;
  final Function(ScribbleItem item)? onView;
  final bool isHeartReacted;

  const MultiScribbleSlider({
    super.key,
    required this.items,
    required this.partnerName,
    required this.connectionId,
    required this.onDoubleTap,
    this.onView,
    this.isHeartReacted = false,
  });

  @override
  State<MultiScribbleSlider> createState() => _MultiScribbleSliderState();
}

class _MultiScribbleSliderState extends State<MultiScribbleSlider> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat.MMMd().add_jm().format(dt.toLocal());
  }

  Widget _buildImage(String url) {
    if (url.isEmpty) return const SizedBox.shrink();

    if (url.startsWith('data:image')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        final base64String = url.substring(commaIndex + 1);
        try {
          return Image.memory(
            base64Decode(base64String),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 32),
            ),
          );
        } catch (_) {}
      }
    }

    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: AppColors.primaryContainer,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 32),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Container(
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.surfaceContainerHigh),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.brush_outlined, size: 28, color: AppColors.outlineVariant),
              const SizedBox(height: 6),
              Text(
                'No active scribble',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                'Tap Reply to send a doodle',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.outline,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasMultiple = widget.items.length > 1;
    final currentItem = widget.items[_currentIndex.clamp(0, widget.items.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sub-header: Sender, Multiple Indicator Pill, and Current Slide Time
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(
                  '${widget.partnerName} → You',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                if (hasMultiple) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer.withAlpha(35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryContainer.withAlpha(80), width: 0.8),
                    ),
                    child: Text(
                      '${_currentIndex + 1} of ${widget.items.length}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              _formatTime(currentItem.createdAt),
              style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.outline),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Carousel Canvas Area
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 155,
            width: double.infinity,
            color: Colors.white,
            child: Stack(
              children: [
                // Notebook Lined Background
                Positioned.fill(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      5,
                      (_) => Container(height: 1, color: AppColors.outlineVariant.withAlpha(70)),
                    ),
                  ),
                ),

                // Slideable PageView of Scribbles
                Positioned.fill(
                  child: GestureDetector(
                    onDoubleTap: widget.onDoubleTap,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: widget.items.length,
                      onPageChanged: (idx) {
                        setState(() => _currentIndex = idx);
                      },
                      itemBuilder: (context, idx) {
                        final item = widget.items[idx];
                        return GestureDetector(
                          onTap: () => widget.onView?.call(item),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: _buildImage(item.imageUrl),
                              ),
                              if (item.textContent != null && item.textContent!.isNotEmpty)
                                Positioned(
                                  bottom: 8,
                                  left: 12,
                                  right: 12,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(160),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      item.textContent!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
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

                // Previous Slide Arrow (when multiple slides)
                if (hasMultiple && _currentIndex > 0)
                  Positioned(
                    left: 6,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.onSurface),
                        ),
                      ),
                    ),
                  ),

                // Next Slide Arrow (when multiple slides)
                if (hasMultiple && _currentIndex < widget.items.length - 1)
                  Positioned(
                    right: 6,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: GestureDetector(
                        onTap: () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(220),
                            shape: BoxShape.circle,
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                          ),
                          child: const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.onSurface),
                        ),
                      ),
                    ),
                  ),

                // Double-tap Animated Floating Heart Reaction
                if (widget.isHeartReacted)
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.elasticOut,
                      builder: (context, val, child) {
                        return Center(
                          child: Transform.scale(
                            scale: val * 1.5,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
                              ),
                              child: const Icon(Icons.favorite_rounded, color: AppColors.primary, size: 36),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Carousel Dot Indicators & Swipe Hint (if multiple scribbles)
        if (hasMultiple) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, (idx) {
                  final isCurrent = idx == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 4),
                    width: isCurrent ? 16 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isCurrent ? AppColors.primaryContainer : AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.swipe_rounded, size: 12, color: AppColors.outline),
                  const SizedBox(width: 4),
                  Text(
                    'Swipe for more notes',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}
