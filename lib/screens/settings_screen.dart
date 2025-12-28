import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/extension_manager_service.dart';
import '../services/import_folder_service.dart';
import '../services/import_processor_service.dart';
import '../services/import_log_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/ai_match_review_sheet.dart';
import '../widgets/custom_title_bar.dart';
import 'auth_screen.dart';

// --- Models ---

enum SettingsCategory {
  subscription,
  autoImport,
  pendingReviews,
  logs,
  account,
  about,
}

extension SettingsCategoryExtension on SettingsCategory {
  String get label {
    switch (this) {
      case SettingsCategory.subscription:
        return 'Subscription';
      case SettingsCategory.account:
        return 'Account';
      case SettingsCategory.autoImport:
        return 'Auto Import';
      case SettingsCategory.pendingReviews:
        return 'Pending Reviews';
      case SettingsCategory.logs:
        return 'Import Logs';
      case SettingsCategory.about:
        return 'About';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsCategory.subscription:
        return Icons.workspace_premium_outlined;
      case SettingsCategory.account:
        return Icons.person_outline;
      case SettingsCategory.autoImport:
        return Icons.cloud_upload_outlined;
      case SettingsCategory.pendingReviews:
        return Icons.rate_review_outlined;
      case SettingsCategory.logs:
        return Icons.terminal;
      case SettingsCategory.about:
        return Icons.info_outline;
    }
  }
}

// --- Main Settings Screen ---

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  SettingsCategory _selectedCategory = SettingsCategory.autoImport;
  bool _isMobile = false;

  @override
  Widget build(BuildContext context) {
    // Check screen width for responsiveness
    _isMobile = MediaQuery.of(context).size.width < 800;

    // Use TitleBarScaffold to wrap the entire layout
    return TitleBarScaffold(
      title: 'KioKuu',
      body: Scaffold(
        backgroundColor: Colors.black,
        body: _isMobile ? _buildMobileLayout() : _buildDesktopLayout(),
      ),
    );
  }

  // --- Mobile Layout ---
  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Mobile Header
        Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            bottom: 16,
          ),
          color: Colors.black,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              const Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Category List
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: SettingsCategory.values.map((category) {
              return ListTile(
                leading: Icon(category.icon, color: Colors.grey[400]),
                title: Text(
                  category.label,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _MobileDetailScreen(category: category),
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ),

        // Bottom Stats (Mobile Version)
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: _AppStats(compact: true),
        ),
      ],
    );
  }

  // --- Desktop Layout ---
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        Container(
          width: 260,
          color: Colors.black, // Match main app theme
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'SETTINGS',
                      style: GoogleFonts.inter(
                        color: Colors.grey[500],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Navigation Items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: SettingsCategory.values.map((category) {
                    final isSelected = category == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Material(
                        color: isSelected
                            ? Colors.white.withOpacity(0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () =>
                              setState(() => _selectedCategory = category),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  category.icon,
                                  size: 18,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey[500],
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  category.label,
                                  style: GoogleFonts.inter(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.grey[400],
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              // App Stats Footer
              const _AppStats(),
            ],
          ),
        ),

        // Vertical Divider
        Container(width: 1, color: Colors.white.withOpacity(0.05)),

        // Content Area
        Expanded(
          child: Container(
            color: Colors.black,
            child: _SettingsContent(category: _selectedCategory),
          ),
        ),
      ],
    );
  }
}

// --- Mobile Detail Screen ---

class _MobileDetailScreen extends StatelessWidget {
  final SettingsCategory category;

  const _MobileDetailScreen({required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          category.label,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: _SettingsContent(category: category),
    );
  }
}

// --- Content Widget ---

class _SettingsContent extends StatefulWidget {
  final SettingsCategory category;

  const _SettingsContent({required this.category});

  @override
  State<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends State<_SettingsContent> {
  final _api = ApiService();
  String? _importFolderPath;

  // Track downloading state per extension
  final Map<String, bool> _isDownloading = {};
  final Map<String, double> _downloadProgress = {};

  // Subscription state
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _plans;
  bool _isLoadingSubscription = true;

  @override
  void initState() {
    super.initState();
    _refreshState();
    _loadSubscription();
  }

  @override
  void didUpdateWidget(_SettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _refreshState();
      if (widget.category == SettingsCategory.subscription) {
        _loadSubscription();
      }
    }
  }

  void _refreshState() {
    _importFolderPath = ImportFolderService.instance.importFolderPath;
    setState(() {});
  }

  Future<void> _loadSubscription() async {
    if (!mounted) return;
    setState(() => _isLoadingSubscription = true);

    final results = await Future.wait([
      _api.getSubscription(),
      _api.getSubscriptionPlans(),
    ]);

    if (mounted) {
      setState(() {
        _subscription = results[0];
        _plans = results[1];
        _isLoadingSubscription = false;
      });
    }
  }

  Future<void> _downloadExtension(String extensionId) async {
    setState(() {
      _isDownloading[extensionId] = true;
      _downloadProgress[extensionId] = 0.0;
    });

    final success = await ExtensionManagerService.instance.downloadExtension(
      extensionId,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress[extensionId] = progress);
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDownloading[extensionId] = false;
      });
      if (success) {
        ImportProcessorService.instance.onAIExtensionInstalled();
        final ext = ExtensionManagerService.instance.getExtensionInfo(
          extensionId,
        );
        AppSnackbar.success(context, '${ext?.name ?? extensionId} installed!');
      }
    }
  }

  Future<void> _uninstallExtension(String extensionId) async {
    final ext = ExtensionManagerService.instance.getExtensionInfo(extensionId);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'Uninstall ${ext?.name}?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You can download it again anytime.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Uninstall',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ExtensionManagerService.instance.uninstallExtension(extensionId);
      setState(() {});
    }
  }

  Future<void> _logout() async {
    await _api.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: MediaQuery.of(context).size.width < 600
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
      children: [
        // Title
        if (MediaQuery.of(context).size.width >= 600)
          Text(
            widget.category.label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        const SizedBox(height: 12),
        Text(
          _getCategoryDescription(widget.category),
          style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 15),
        ),
        const SizedBox(height: 48),

        // Content
        if (widget.category == SettingsCategory.subscription)
          _buildSubscriptionContent(),
        if (widget.category == SettingsCategory.autoImport)
          _buildAutoImportContent(),
        if (widget.category == SettingsCategory.pendingReviews)
          _buildPendingReviewsContent(),
        if (widget.category == SettingsCategory.logs) _buildLogsContent(),
        if (widget.category == SettingsCategory.account) _buildAccountContent(),
        if (widget.category == SettingsCategory.about) _buildAboutContent(),
      ],
    );
  }

  String _getCategoryDescription(SettingsCategory category) {
    switch (category) {
      case SettingsCategory.subscription:
        return 'Choose a plan that fits your needs.';
      case SettingsCategory.account:
        return 'Manage your account and session.';
      case SettingsCategory.autoImport:
        return 'Configure how files are automatically imported into your library.';
      case SettingsCategory.pendingReviews:
        return 'Review and approve AI-matched songs before uploading.';
      case SettingsCategory.logs:
        return 'View real-time AI processing activity.';
      case SettingsCategory.about:
        return 'Information about KioKuu.';
    }
  }

  // --- Content Builders ---

  // State for billing cycle selection (separate for each plan)
  String _basicBillingCycle = 'yearly';
  String _proBillingCycle = 'yearly';
  String _selectedPlan = 'pro'; // 'basic' or 'pro' (for mobile toggle)
  bool _isCheckingOut = false;

  /// Handle subscription checkout
  Future<void> _handleSubscribe(String plan, String billingCycle) async {
    if (_isCheckingOut) return;

    setState(() => _isCheckingOut = true);

    try {
      final checkoutUrl = await _api.createCheckoutSession(
        plan: plan,
        billingCycle: billingCycle,
      );

      if (checkoutUrl != null) {
        final uri = Uri.parse(checkoutUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          if (mounted) {
            AppSnackbar.error(context, 'Could not open checkout page');
          }
        }
      } else {
        if (mounted) {
          AppSnackbar.error(context, 'Failed to create checkout session');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingOut = false);
      }
    }
  }

  Widget _buildSubscriptionContent() {
    // Show loading state
    if (_isLoadingSubscription) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    // Get current subscription info
    final currentPlan = _subscription?['plan'] ?? 'free';
    final isSubscribed = currentPlan != 'free';
    final storageLimitGB = _subscription?['storage_limit_gb'] ?? 0;
    final storageUsedBytes = _subscription?['storage_used_bytes'] ?? 0;
    final storageUsedGB = (storageUsedBytes / (1024 * 1024 * 1024))
        .toStringAsFixed(1);
    final features = _subscription?['features'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current Subscription Status Banner (if subscribed)
        if (isSubscribed) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                colors: currentPlan == 'pro'
                    ? [
                        const Color(0xFF7B68EE).withOpacity(0.3),
                        const Color(0xFF1A1A2E),
                      ]
                    : [Colors.grey.withOpacity(0.2), const Color(0xFF1A1A1A)],
              ),
              border: Border.all(
                color: currentPlan == 'pro'
                    ? const Color(0xFF7B68EE).withOpacity(0.5)
                    : Colors.grey.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: currentPlan == 'pro'
                        ? const Color(0xFF7B68EE).withOpacity(0.2)
                        : Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    currentPlan == 'pro'
                        ? Icons.auto_awesome
                        : Icons.cloud_outlined,
                    color: currentPlan == 'pro'
                        ? const Color(0xFF7B68EE)
                        : Colors.grey,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'KioKuu ${currentPlan == 'pro' ? 'Pro' : 'Basic'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Storage: $storageUsedGB / ${storageLimitGB}GB used',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        // Header
        Center(
          child: Column(
            children: [
              Text(
                isSubscribed
                    ? 'Manage your subscription'
                    : 'Your music, your cloud.',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isSubscribed
                    ? 'Upgrade, change billing, or manage your plan.'
                    : 'Choose a plan that fits your needs.',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Plan Cards - Side by side on larger screens
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;

            if (isWide) {
              // Side by side layout for larger screens
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildBasicPlanCard()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildProPlanCard()),
                  ],
                ),
              );
            } else {
              // Stacked layout with toggle for smaller screens
              return Column(
                children: [
                  // Plan Selection Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => _selectedPlan = 'basic'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedPlan == 'basic'
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  'Basic',
                                  style: TextStyle(
                                    color: _selectedPlan == 'basic'
                                        ? Colors.white
                                        : Colors.grey[500],
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedPlan = 'pro'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _selectedPlan == 'pro'
                                    ? const Color(0xFF7B68EE).withOpacity(0.2)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: _selectedPlan == 'pro'
                                    ? Border.all(
                                        color: const Color(
                                          0xFF7B68EE,
                                        ).withOpacity(0.5),
                                      )
                                    : null,
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Pro',
                                      style: TextStyle(
                                        color: _selectedPlan == 'pro'
                                            ? Colors.white
                                            : Colors.grey[500],
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Color(0xFF7B68EE),
                                            Color(0xFF9B7DFF),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'AI',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Single card based on selection
                  if (_selectedPlan == 'basic') _buildBasicPlanCard(),
                  if (_selectedPlan == 'pro') _buildProPlanCard(),
                ],
              );
            }
          },
        ),

        const SizedBox(height: 24),

        // Security Notice
        Center(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.grey, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    '256-BIT ENCRYPTED',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 11,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Secure encryption. You own your data.',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              Text(
                'Cancel anytime.',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBasicPlanCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.3), width: 1.5),
        color: const Color(0xFF1A1A1A),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KioKuu Basic',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Essential cloud storage',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_outlined,
                    color: Colors.grey,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Storage Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.storage_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '100GB Storage',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
                Text(
                  '~20k Songs',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),

            // Features List
            _buildFeatureRow(
              Icons.cloud_upload_outlined,
              'Cloud Storage',
              'Store and sync your music library',
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.play_circle_outline,
              'Unlimited Playback',
              'Stream your entire library',
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.playlist_play_outlined,
              'Unlimited Playlists',
              'Organize your music your way',
            ),
            const SizedBox(height: 24),

            // Billing Cycle Selection
            _buildBillingSection(isProPlan: false),

            const SizedBox(height: 24),

            // Subscribe Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCheckingOut
                    ? null
                    : () => _handleSubscribe('basic', _basicBillingCycle),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isCheckingOut
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Text(
                        'Subscribe to Basic',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProPlanCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF7B68EE).withOpacity(0.5),
          width: 1.5,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1A1A2E), Colors.black.withOpacity(0.95)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'KioKuu Pro',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7B68EE), Color(0xFF9B7DFF)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'AI POWERED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Unlock full power & AI features',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B68EE).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Color(0xFF7B68EE),
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Storage Info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.storage_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '500GB Storage',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
                Text(
                  '~100k Songs',
                  style: TextStyle(color: Colors.grey[400], fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(
                  colors: [Color(0xFF7B68EE), Color(0xFF9B7DFF)],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Features List - Everything in Basic plus AI
            _buildFeatureRow(
              Icons.check_circle_outline,
              'Everything in Basic',
              'All basic features included',
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.auto_awesome_outlined,
              'AI Auto Import',
              'Smart tagging: BPM, Key, Mood & Genre',
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.psychology_outlined,
              'Deep AI Analysis',
              'Advanced metadata & song matching',
            ),
            const SizedBox(height: 16),
            _buildFeatureRow(
              Icons.cloud_upload_outlined,
              '5x More Storage',
              '500GB vs 100GB in Basic',
            ),
            const SizedBox(height: 24),

            // Billing Cycle Selection
            _buildBillingSection(isProPlan: true),

            const SizedBox(height: 24),

            // Subscribe Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCheckingOut
                    ? null
                    : () => _handleSubscribe('pro', _proBillingCycle),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B68EE),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(
                    0xFF7B68EE,
                  ).withOpacity(0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isCheckingOut
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      )
                    : const Text(
                        'Subscribe to Pro',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingSection({required bool isProPlan}) {
    // Basic: $2.50, $5, $9, $100
    // Pro: $5, $9, $19 (no lifetime)
    final basePrice = isProPlan ? 5.00 : 2.50;
    final sixMonthPrice = isProPlan ? 9.00 : 5.00;
    final yearlyPrice = isProPlan ? 19.00 : 9.00;
    final yearlyOriginal = isProPlan ? 60.00 : 30.00;
    final lifetimePrice = 100.00; // Only for Basic
    final monthlyRate = isProPlan ? 1.58 : 0.75;

    // Use separate state for each plan
    final selectedCycle = isProPlan ? _proBillingCycle : _basicBillingCycle;
    void selectCycle(String cycle) {
      setState(() {
        if (isProPlan) {
          _proBillingCycle = cycle;
        } else {
          _basicBillingCycle = cycle;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT BILLING CYCLE',
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 12),
        _buildBillingOption(
          id: 'monthly',
          title: 'Monthly',
          price: '\$${basePrice.toStringAsFixed(2)}',
          isSelected: selectedCycle == 'monthly',
          onTap: () => selectCycle('monthly'),
        ),
        const SizedBox(height: 8),
        _buildBillingOption(
          id: '6months',
          title: '6 Months',
          price: '\$${sixMonthPrice.toStringAsFixed(2)}',
          isSelected: selectedCycle == '6months',
          onTap: () => selectCycle('6months'),
        ),
        const SizedBox(height: 8),
        _buildBillingOption(
          id: 'yearly',
          title: 'Yearly',
          badge: 'BEST VALUE',
          price: '\$${yearlyPrice.toStringAsFixed(2)}',
          originalPrice: '\$${yearlyOriginal.toStringAsFixed(2)}',
          subtitle: 'only \$${monthlyRate.toStringAsFixed(2)}/mo',
          isSelected: selectedCycle == 'yearly',
          onTap: () => selectCycle('yearly'),
        ),
        // Lifetime only for Basic plan
        if (!isProPlan) ...[
          const SizedBox(height: 8),
          _buildBillingOption(
            id: 'lifetime',
            title: 'Lifetime',
            badge: 'LIMITED',
            badgeColor: Colors.grey,
            price: '\$${lifetimePrice.toStringAsFixed(2)}',
            isSelected: selectedCycle == 'lifetime',
            onTap: () => selectCycle('lifetime'),
          ),
        ],
      ],
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white70, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBillingOption({
    required String id,
    required String title,
    required String price,
    String? badge,
    Color? badgeColor,
    String? originalPrice,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF7B68EE)
                : Colors.grey.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? const Color(0xFF7B68EE).withOpacity(0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            // Radio circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF7B68EE)
                      : Colors.grey.withOpacity(0.5),
                  width: 2,
                ),
                color: isSelected
                    ? const Color(0xFF7B68EE)
                    : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 12),
            // Title and badge
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey[300],
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? const Color(0xFF7B68EE))
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: badgeColor ?? const Color(0xFF7B68EE),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Price
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (originalPrice != null)
                      Text(
                        originalPrice,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (originalPrice != null) const SizedBox(width: 6),
                    Text(
                      price,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[300],
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: const Color(0xFF7B68EE),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoImportContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Watched Folder'),
        _SettingsCard(
          child: Column(
            children: [
              ListTile(
                title: const Text(
                  'Import Path',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _importFolderPath ?? 'Not available',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.folder_open, color: Colors.white70),
                  onPressed: () {
                    AppSnackbar.info(
                      context,
                      message: 'Folder: $_importFolderPath',
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Audio files dropped here will be processed automatically.',
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        _SectionHeader('Extensions'),
        Text(
          'Choose which identification methods to use. You can enable multiple for best results.',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Dynamic extension list
        ...ExtensionManagerService.availableExtensions.map(
          (ext) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildExtensionCard(ext),
          ),
        ),

        if (ImportProcessorService.instance.pendingTasks.isNotEmpty) ...[
          const SizedBox(height: 32),
          _SectionHeader('Pending Tasks'),
          _SettingsCard(
            child: ListTile(
              leading: const Icon(Icons.timer, color: Colors.orange),
              title: Text(
                '${ImportProcessorService.instance.pendingTasks.length} files waiting',
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Install an extension to process',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPendingReviewsContent() {
    final reviewTasks = ImportProcessorService.instance.tasks
        .where((t) => t.status == ImportStatus.awaitingReview)
        .toList();

    if (reviewTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                borderRadius: BorderRadius.circular(40),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Colors.green,
                size: 44,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'All caught up!',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'No files waiting for review',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE040FB).withAlpha(20),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE040FB).withAlpha(50)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFFE040FB),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${reviewTasks.length} file${reviewTasks.length > 1 ? 's' : ''} need${reviewTasks.length == 1 ? 's' : ''} your review',
                  style: const TextStyle(
                    color: Color(0xFFE040FB),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Task list
        ...reviewTasks.map((task) => _buildReviewTaskCard(task)),
      ],
    );
  }

  Widget _buildReviewTaskCard(ImportTask task) {
    final hasMatch = task.aiMatchResult != null;
    final match = task.aiMatchResult;
    final confidence = hasMatch
        ? (match!.confidence * 100).toStringAsFixed(0)
        : null;
    final albumArt = hasMatch ? match!.albumArt : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: _SettingsCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row with file info
              Row(
                children: [
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: albumArt != null && albumArt.isNotEmpty
                        ? Image.network(
                            albumArt,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(64),
                          )
                        : _buildPlaceholder(64),
                  ),
                  const SizedBox(width: 16),
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasMatch) ...[
                          Text(
                            match!.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            match.artist,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else ...[
                          Text(
                            task.title ?? task.fileName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            task.artist ?? 'Unknown artist',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Confidence or no match badge
                            if (hasMatch)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _getConfidenceColor(
                                    match!.confidence,
                                  ).withAlpha(40),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$confidence% confident',
                                  style: TextStyle(
                                    color: _getConfidenceColor(
                                      match.confidence,
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.withAlpha(40),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'No match found',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            // File name
                            Flexible(
                              child: Text(
                                task.fileName,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  if (hasMatch)
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ImportProcessorService.instance.acceptMatch(
                            task,
                            spotifyId: match!.spotifyId,
                            title: match.title,
                            artist: match.artist,
                            album: match.album,
                          );
                          setState(() {});
                        },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  if (hasMatch) const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _openReviewSheet(task);
                      },
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Search'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ImportProcessorService.instance.rejectMatch(task);
                        setState(() {});
                      },
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Skip'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openReviewSheet(ImportTask task) {
    AIMatchReviewSheet.show(
      context,
      fileName: task.fileName,
      extractedTitle: task.title,
      extractedArtist: task.artist,
      extractedAlbum: task.album,
      aiMatch: task.aiMatchResult,
      onAccept: (spotifyId, title, artist, album) {
        ImportProcessorService.instance.acceptMatch(
          task,
          spotifyId: spotifyId,
          title: title,
          artist: artist,
          album: album,
        );
        setState(() {});
      },
      onReject: () {
        ImportProcessorService.instance.rejectMatch(task);
        setState(() {});
      },
    );
  }

  Widget _buildPlaceholder(double size) {
    return Container(
      width: size,
      height: size,
      color: Colors.grey[850],
      child: Icon(Icons.music_note, color: Colors.grey[600], size: size * 0.5),
    );
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.6) return Colors.orange;
    return Colors.redAccent;
  }

  Widget _buildExtensionCard(ExtensionInfo ext) {
    final isInstalled = ExtensionManagerService.instance.isInstalled(ext.id);
    final isEnabled = ExtensionManagerService.instance.isEnabled(ext.id);
    final isDownloading = _isDownloading[ext.id] ?? false;
    final progress = _downloadProgress[ext.id] ?? 0.0;

    // Smart Match uses API key, not download
    final isApiBasedExtension = ext.downloadUrl.isEmpty;

    // Choose icon based on extension type
    IconData icon;
    Color iconColor;
    Color iconBgColor;
    switch (ext.iconType) {
      case IconType.ai:
        icon = Icons.auto_awesome;
        iconColor = Colors.white;
        iconBgColor = Colors.white.withOpacity(0.15);
      case IconType.generic:
        icon = Icons.extension;
        iconColor = Colors.grey;
        iconBgColor = Colors.grey.withOpacity(0.15);
    }

    return _SettingsCard(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              ext.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (isEnabled) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Model name
                      Text(
                        ext.modelName,
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ext.description,
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // API Key Configuration for Smart Match
            if (isApiBasedExtension) ...[
              const SizedBox(height: 16),
              _buildApiKeySection(ext.id),
            ] else ...[
              // Download-based extension UI
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isDownloading)
                    SizedBox(
                      width: 120,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[800],
                            color: iconColor,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(progress * 100).toInt()}%',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isInstalled)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isEnabled,
                          onChanged: (value) {
                            ExtensionManagerService.instance.setEnabled(
                              ext.id,
                              value,
                            );
                            setState(() {});
                          },
                          activeColor: Colors.white,
                          activeTrackColor: Colors.white,
                          inactiveThumbColor: Colors.grey[400],
                          inactiveTrackColor: Colors.grey[800],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () => _uninstallExtension(ext.id),
                          tooltip: 'Uninstall',
                        ),
                      ],
                    )
                  else
                    ElevatedButton(
                      onPressed: () => _downloadExtension(ext.id),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        'Download (${ExtensionManagerService.instance.getFormattedSize(ext.id)})',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeySection(String extensionId) {
    // Smart Match is backend-based - just show subscription info
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cloud AI Active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Premium+ subscribers get AI-powered matching for accurate original artist detection.',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsContent() {
    return StreamBuilder<List<LogEntry>>(
      stream: ImportLogService.instance.logStream,
      initialData: ImportLogService.instance.logs,
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SectionHeader('Activity Log'),
                const Spacer(),
                if (logs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      ImportLogService.instance.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey),
                  ),
              ],
            ),
            _SettingsCard(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 400),
                child: logs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.inbox_outlined,
                                size: 48,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No import activity yet',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Drop files into your import folder to see AI processing logs here',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        reverse: true, // Show newest first
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final log = logs[logs.length - 1 - index];
                          return _buildLogEntry(log);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 24),
            _SectionHeader('Legend'),
            _SettingsCard(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _buildLegendItem(
                      Icons.psychology,
                      'AI Thinking',
                      Colors.purple,
                    ),
                    _buildLegendItem(Icons.info_outline, 'Info', Colors.blue),
                    _buildLegendItem(
                      Icons.check_circle_outline,
                      'Success',
                      Colors.green,
                    ),
                    _buildLegendItem(
                      Icons.warning_amber_outlined,
                      'Warning',
                      Colors.orange,
                    ),
                    _buildLegendItem(Icons.error_outline, 'Error', Colors.red),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLogEntry(LogEntry log) {
    Color textColor;
    Color bgColor;

    switch (log.type) {
      case LogType.aiThinking:
        textColor = Colors.purple[300]!;
        bgColor = Colors.purple.withOpacity(0.1);
      case LogType.success:
        textColor = Colors.green[300]!;
        bgColor = Colors.green.withOpacity(0.1);
      case LogType.warning:
        textColor = Colors.orange[300]!;
        bgColor = Colors.orange.withOpacity(0.1);
      case LogType.error:
        textColor = Colors.red[300]!;
        bgColor = Colors.red.withOpacity(0.1);
      case LogType.info:
        textColor = Colors.grey[400]!;
        bgColor = Colors.transparent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(log.iconData, size: 16, color: log.color),
              const SizedBox(width: 8),
              Text(
                log.timeFormatted,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  log.message,
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
              ),
            ],
          ),
          if (log.details != null) ...[
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 4),
              child: Text(
                log.details!,
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }

  Widget _buildAccountContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Session'),
        _SettingsCard(
          child: ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Sign out of your account on this device',
              style: TextStyle(color: Colors.grey),
            ),
            onTap: _logout,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.music_note,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KioKuu',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'v1.0.0 (Beta)',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// --- Helper UI Components ---

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(
        title,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;
  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212), // Slightly lighter than black bg
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _AppStats extends StatefulWidget {
  final bool compact;
  const _AppStats({this.compact = false});

  @override
  State<_AppStats> createState() => _AppStatsState();
}

class _AppStatsState extends State<_AppStats> {
  String _username = '...';

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final username = await ApiService().username;
    if (mounted) {
      setState(() {
        _username = username ?? 'Unknown';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(widget.compact ? 0 : 24, 24, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'APP STATS',
            style: GoogleFonts.inter(
              color: Colors.grey[700],
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          _StatRow('Client Version', '1.0.0'),
          const SizedBox(height: 6),
          _StatRow('Platform', Platform.operatingSystem),
          const SizedBox(height: 6),
          _StatRow('User ID', _username),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label ',
          style: TextStyle(color: Colors.grey[600], fontSize: 11),
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
