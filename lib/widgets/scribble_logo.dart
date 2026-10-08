import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

class ScribbleLogo extends StatelessWidget {
  final double size;
  final double? borderRadius;
  final bool showGlow;

  const ScribbleLogo({
    super.key,
    this.size = 40,
    this.borderRadius,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? (size * 0.26);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: showGlow
            ? [
                BoxShadow(
                  color: AppColors.primary.withAlpha(70),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/images/app_logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            // Elegant Vector Fallback
            return Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E1F29), Color(0xFF0F1015)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: AppColors.primaryContainer.withAlpha(90), width: 1.5),
              ),
              child: Center(
                child: Icon(
                  Icons.draw_rounded,
                  size: size * 0.55,
                  color: AppColors.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ScribbleBrandHeader extends StatelessWidget {
  final double logoSize;
  final String title;
  final String? subtitle;
  final CrossAxisAlignment crossAxisAlignment;

  const ScribbleBrandHeader({
    super.key,
    this.logoSize = 36,
    this.title = 'Scribble',
    this.subtitle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ScribbleLogo(size: logoSize),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: crossAxisAlignment,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: logoSize * 0.5,
                fontWeight: FontWeight.w800,
                color: AppColors.onSurface,
                height: 1.1,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 1),
              Text(
                subtitle!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: logoSize * 0.3,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
