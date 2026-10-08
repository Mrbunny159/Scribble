import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/connection_model.dart';
import '../../services/firebase_service.dart';

class PairingScreen extends StatefulWidget {
  final VoidCallback onConnectionsChanged;

  const PairingScreen({super.key, required this.onConnectionsChanged});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _codeController = TextEditingController();
  String? _myGeneratedCode;
  bool _isLoadingCode = false;
  bool _isClaimingCode = false;
  bool _isLoadingConnections = true;
  List<ConnectionModel> _connections = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingConnections = true);
    try {
      final list = await FirebaseService().getConnections();
      if (mounted) {
        setState(() {
          _connections = list;
          _isLoadingConnections = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingConnections = false);
      }
    }
  }

  Future<void> _generateCode() async {
    setState(() => _isLoadingCode = true);
    try {
      final code = await FirebaseService().generatePairingCode();
      if (mounted) {
        setState(() {
          _myGeneratedCode = code;
          _isLoadingCode = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate code: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _claimCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-character code'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isClaimingCode = true);
    try {
      final conn = await FirebaseService().claimPairingCode(code);
      _codeController.clear();
      await _loadData();
      widget.onConnectionsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected with ${conn.partnerProfile?.username ?? "Friend"}!'),
            backgroundColor: AppColors.secondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClaimingCode = false);
      }
    }
  }

  Future<void> _removeConnection(String connId, String partnerName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Disconnect from $partnerName?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold)),
        content: Text('You will no longer exchange lock screen scribbles with each other.', style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(color: AppColors.outline)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Disconnect', style: GoogleFonts.plusJakartaSans()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseService().removeConnection(connId);
      await _loadData();
      widget.onConnectionsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primaryContainer,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pair and Connect',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Link phones to exchange live handwritten notes directly onto each other\'s lock screen.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),

                  // Section 1: Your Pairing Code Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your Pairing Code',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_myGeneratedCode != null) ...[
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: _myGeneratedCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 2)),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.primaryFixed),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _myGeneratedCode!,
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 32,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 6,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Share this code with your friend. Valid for 24 hours.',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.outline),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: _isLoadingCode ? null : _generateCode,
                            icon: _isLoadingCode
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.key_rounded, size: 18, color: Colors.white),
                            label: Text(
                              _isLoadingCode ? 'Generating...' : 'Generate New Code',
                              style: const TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryContainer,
                              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Section 2: Enter Friend's Code
                  Text(
                    'Enter Friend\'s Code',
                    style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 6,
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            hintText: '6-CHAR CODE',
                            counterText: '',
                            prefixIcon: Icon(Icons.pin_rounded, color: AppColors.primary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isClaimingCode ? null : _claimCode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondary,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: _isClaimingCode
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text(
                                  'Connect',
                                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Section 3: Connected Users
                  Row(
                    children: [
                      Text(
                        'Connected Friends',
                        style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryFixed,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_connections.length}',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_isLoadingConnections)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: AppColors.primaryContainer),
                      ),
                    )
                  else if (_connections.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.surfaceContainerHigh),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.people_outline_rounded, size: 44, color: AppColors.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No connected friends yet',
                            style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Generate a code or enter your friend\'s code above to start scribbling!',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.outline),
                          ),
                        ],
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _connections.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final conn = _connections[index];
                        final partner = conn.partnerProfile;
                        final partnerName = partner?.username ?? 'Anonymous Scribbler';
                        final dateFormatted = DateFormat.yMMMd().format(conn.createdAt);

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10),
                            ],
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: AppColors.primaryFixed,
                                backgroundImage: partner?.avatarUrl != null ? NetworkImage(partner!.avatarUrl!) : null,
                                child: partner?.avatarUrl == null
                                    ? Text(
                                        partnerName.isNotEmpty ? partnerName[0].toUpperCase() : '?',
                                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      partnerName,
                                      style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.onSurface),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Paired on $dateFormatted',
                                      style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.outline),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.link_off_rounded, color: AppColors.error, size: 20),
                                onPressed: () => _removeConnection(conn.id, partnerName),
                                tooltip: 'Disconnect',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
