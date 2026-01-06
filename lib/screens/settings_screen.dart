import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../services/api_service.dart';
import '../services/discord_rpc_service.dart';
import '../services/extension_manager_service.dart';
import '../services/import_folder_service.dart';
import '../services/import_processor_service.dart';
import '../services/import_watcher_service.dart';
import '../services/import_log_service.dart';
import '../services/storage_management_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/ai_match_review_sheet.dart';
import '../widgets/custom_title_bar.dart';
import '../config/app_config.dart';
import '../services/extension_runtime_service.dart';
import '../models/extension_model.dart';
import 'auth_screen.dart';

// --- Models ---

enum SettingsCategory {
  subscription,
  usage,
  storage,
  connections,
  extensions,
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
      case SettingsCategory.usage:
        return 'Usage';
      case SettingsCategory.storage:
        return 'Storage';
      case SettingsCategory.connections:
        return 'Connections';
      case SettingsCategory.account:
        return 'Account';
      case SettingsCategory.extensions:
        return 'Extensions';
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
      case SettingsCategory.usage:
        return Icons.bar_chart_rounded;
      case SettingsCategory.storage:
        return Icons.storage_rounded;
      case SettingsCategory.connections:
        return Icons.link;
      case SettingsCategory.account:
        return Icons.person_outline;
      case SettingsCategory.extensions:
        return Icons.extension;
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
            children: SettingsCategory.values
                .where((c) => c != SettingsCategory.subscription)
                .map((category) {
                  return ListTile(
                    leading: Icon(category.icon, color: Colors.grey[400]),
                    title: Text(
                      category.label,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              _MobileDetailScreen(category: category),
                        ),
                      );
                    },
                  );
                })
                .toList(),
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
                  children: SettingsCategory.values
                      .where((c) => c != SettingsCategory.subscription)
                      .map((category) {
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
                      })
                      .toList(),
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
  String _appVersion = '...';

  // Track downloading state per extension
  final Map<String, bool> _isDownloading = {};
  final Map<String, double> _downloadProgress = {};
  // Extension updates
  Map<String, String> _availableUpdates = {};
  bool _isCheckingUpdates = false;

  // Subscription state
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _plans;
  bool _isLoadingSubscription = true;
  bool _isLoggingOut = false;

  // Timer for refreshing pending reviews
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshState();
    _loadSubscription();
    _loadAppVersion();
    _startRefreshTimerIfNeeded();
  }

  @override
  void didUpdateWidget(_SettingsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      _refreshState();
      if (widget.category == SettingsCategory.subscription) {
        _loadSubscription();
      }
      if (widget.category == SettingsCategory.extensions) {
        _checkForExtensionUpdates(showSnackbar: false);
      }
      _startRefreshTimerIfNeeded();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimerIfNeeded() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // Only refresh periodically when viewing pending reviews
    if (widget.category == SettingsCategory.pendingReviews) {
      _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (mounted) {
          setState(() {});
        }
      });
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

  Future<void> _loadAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
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
    setState(() => _isLoggingOut = true);
    await _api.logout();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _pickImportFolder() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Import Folder',
      );

      if (result != null) {
        final success = await ImportFolderService.instance
            .setCustomImportFolder(result);
        if (success) {
          setState(() {
            _importFolderPath = result;
          });
          if (mounted) {
            AppSnackbar.success(context, 'Import folder updated successfully');
          }
        } else {
          if (mounted) {
            AppSnackbar.error(context, 'Failed to set import folder');
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking folder: $e');
      if (mounted) {
        AppSnackbar.error(context, 'Error selecting folder: $e');
      }
    }
  }

  Future<void> _resetToDefaultFolder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
        title: const Text(
          'Reset to Default Folder?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This will revert to the default KioKuu import folder.',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[400],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ImportFolderService.instance.clearCustomImportFolder();
      setState(() {
        _importFolderPath = ImportFolderService.instance.importFolderPath;
      });
      if (mounted) {
        AppSnackbar.success(context, 'Reverted to default import folder');
      }
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
        if (widget.category == SettingsCategory.usage) _buildUsageContent(),
        if (widget.category == SettingsCategory.storage) _buildStorageContent(),
        if (widget.category == SettingsCategory.connections)
          _buildConnectionsContent(),
        if (widget.category == SettingsCategory.extensions)
          _buildExtensionsContent(),
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
      case SettingsCategory.usage:
        return 'Track your storage, listening activity, and most played songs.';
      case SettingsCategory.storage:
        return 'Manage local storage, cache, and offline content.';
      case SettingsCategory.connections:
        return 'Connect external services to enhance your experience.';
      case SettingsCategory.extensions:
        return 'Import custom extensions to add music sources.';
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

  // Usage state
  Map<String, dynamic>? _usageStats;
  bool _isLoadingUsage = false;

  Future<void> _loadUsageStats() async {
    if (_isLoadingUsage) return;
    setState(() => _isLoadingUsage = true);

    final stats = await _api.getUsageStats();
    if (mounted) {
      setState(() {
        _usageStats = stats;
        _isLoadingUsage = false;
      });
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours < 24) return '${hours}h ${mins}m';
    final days = hours ~/ 24;
    final remainingHours = hours % 24;
    return '${days}d ${remainingHours}h';
  }

  Widget _buildUsageContent() {
    // Load usage stats if not loaded
    if (_usageStats == null && !_isLoadingUsage) {
      _loadUsageStats();
    }

    if (_isLoadingUsage || _usageStats == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    final stats = _usageStats!;
    final storageCountedBytes = (stats['storage_counted_bytes'] ?? 0) as int;
    final storageLimitBytes = (stats['storage_limit_bytes'] ?? 0) as int;
    final storageLimitGB = (stats['storage_limit_gb'] ?? 0) as int;
    final totalSongs = (stats['total_songs'] ?? 0) as int;
    final popularSongCount = (stats['popular_song_count'] ?? 0) as int;
    final totalActiveDays = (stats['total_active_days'] ?? 0) as int;
    final currentStreak = (stats['current_streak'] ?? 0) as int;
    final longestStreak = (stats['longest_streak'] ?? 0) as int;
    final totalListenedMinutes = (stats['total_listened_minutes'] ?? 0) as int;
    final topSongs = (stats['top_songs'] as List<dynamic>?) ?? [];

    final storageCountedGB = storageCountedBytes / (1024 * 1024 * 1024);
    final storagePercent = storageLimitBytes > 0
        ? (storageCountedBytes / storageLimitBytes * 100).clamp(0.0, 100.0)
        : 0.0;

    // Format storage used - show MB if less than 1GB
    final String storageUsedText;
    if (storageCountedGB < 1.0) {
      final storageMB = storageCountedBytes / (1024 * 1024);
      storageUsedText = '${storageMB.toStringAsFixed(0)} MB';
    } else {
      storageUsedText = '${storageCountedGB.toStringAsFixed(1)} GB';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Storage Donut Chart
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF1A1A1A), const Color(0xFF0D0D0D)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Donut chart
              SizedBox(
                height: 200,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 0,
                        centerSpaceRadius: 60,
                        startDegreeOffset: -90,
                        sections: [
                          // Used storage
                          PieChartSectionData(
                            value: storageCountedGB,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6C63FF), Color(0xFF00BFA5)],
                            ),
                            radius: 25,
                            showTitle: false,
                          ),
                          // Available storage
                          PieChartSectionData(
                            value: math.max(
                              0.1,
                              storageLimitGB - storageCountedGB,
                            ),
                            color: const Color(0xFF1F1F1F),
                            radius: 25,
                            showTitle: false,
                          ),
                        ],
                      ),
                    ),
                    // Center text
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${storagePercent.toStringAsFixed(0)}%',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$storageUsedText / $storageLimitGB GB',
                            style: GoogleFonts.inter(
                              color: Colors.grey[400],
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (popularSongCount > 0) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF6C63FF).withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        color: const Color(0xFF6C63FF),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$popularSongCount popular song${popularSongCount > 1 ? 's' : ''} don\'t count toward quota',
                        style: TextStyle(color: Colors.grey[300], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Stats Row
        Row(
          children: [
            Expanded(
              child: _buildMinimalStat(
                totalSongs.toString(),
                'Songs',
                Icons.music_note_rounded,
                const Color(0xFF00BFA5),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMinimalStat(
                _formatMinutes(totalListenedMinutes),
                'Listened',
                Icons.headphones_rounded,
                const Color(0xFF6C63FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMinimalStat(
                totalActiveDays.toString(),
                'Active Days',
                Icons.calendar_today_rounded,
                const Color(0xFFFF6B6B),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMinimalStat(
                '$currentStreak',
                longestStreak > currentStreak
                    ? 'Streak (Best: $longestStreak)'
                    : 'Day Streak',
                Icons.local_fire_department_rounded,
                const Color(0xFFFF9F1C),
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Most Played with bar chart
        if (topSongs.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Songs',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Last 30 days',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF1A1A1A), const Color(0xFF0D0D0D)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              children: [
                // Horizontal bar chart for top 5
                SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY:
                          (topSongs.isNotEmpty
                                  ? (topSongs[0]['play_count'] ?? 1) as num
                                  : 1)
                              .toDouble() *
                          1.15,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => const Color(0xFF2A2A2A),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final song = topSongs[groupIndex];
                            return BarTooltipItem(
                              '${song['title']}\n',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              children: [
                                TextSpan(
                                  text: '${rod.toY.toInt()} plays',
                                  style: TextStyle(
                                    color: const Color(0xFF6C63FF),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx >= 0 &&
                                  idx < math.min(5, topSongs.length)) {
                                final title = topSongs[idx]['title'] ?? '';
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    title.length > 8
                                        ? '${title.substring(0, 8)}...'
                                        : title,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 10,
                                    ),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 5,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.white.withOpacity(0.05),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (int i = 0; i < math.min(5, topSongs.length); i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: ((topSongs[i]['play_count'] ?? 0) as num)
                                    .toDouble(),
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: i == 0
                                      ? [
                                          const Color(0xFF6C63FF),
                                          const Color(0xFF8B85FF),
                                        ]
                                      : [
                                          const Color(
                                            0xFF6C63FF,
                                          ).withOpacity(0.6),
                                          const Color(
                                            0xFF8B85FF,
                                          ).withOpacity(0.6),
                                        ],
                                ),
                                width: 32,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                  topRight: Radius.circular(6),
                                ),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY:
                                      (topSongs[0]['play_count'] as num)
                                          .toDouble() *
                                      1.15,
                                  color: Colors.white.withOpacity(0.02),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Storage management state
  List<StorageCategory>? _storageCategories;
  bool _isLoadingStorage = false;
  bool _isClearingStorage = false;
  String? _clearingCategoryName;

  Future<void> _loadStorageData() async {
    if (_isLoadingStorage) return;
    setState(() => _isLoadingStorage = true);

    try {
      final categories = await StorageManagementService.instance
          .getStorageBreakdown();
      if (mounted) {
        setState(() {
          _storageCategories = categories;
          _isLoadingStorage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStorage = false);
        AppSnackbar.error(context, 'Failed to load storage data');
      }
    }
  }

  IconData _getStorageIcon(StorageIconType type) {
    switch (type) {
      case StorageIconType.offlineSongs:
        return Icons.download_for_offline_rounded;
      case StorageIconType.imageCache:
        return Icons.image_rounded;
      case StorageIconType.playlistCache:
        return Icons.playlist_play_rounded;
      case StorageIconType.lyrics:
        return Icons.lyrics_rounded;
      case StorageIconType.importTasks:
        return Icons.upload_file_rounded;
      case StorageIconType.preferences:
        return Icons.settings_rounded;
      case StorageIconType.tempFiles:
        return Icons.folder_delete_rounded;
    }
  }

  Color _getStorageColor(StorageIconType type) {
    switch (type) {
      case StorageIconType.offlineSongs:
        return const Color(0xFF6C63FF);
      case StorageIconType.imageCache:
        return const Color(0xFF00BFA5);
      case StorageIconType.playlistCache:
        return const Color(0xFFFF6B6B);
      case StorageIconType.lyrics:
        return const Color(0xFFFF9F1C);
      case StorageIconType.importTasks:
        return const Color(0xFF4ECDC4);
      case StorageIconType.preferences:
        return const Color(0xFF9B7DFF);
      case StorageIconType.tempFiles:
        return const Color(0xFFE84855);
    }
  }

  Future<void> _clearStorageCategory(StorageCategory category) async {
    if (category.onClear == null) return;

    // Show confirmation dialog for offline songs
    if (category.iconType == StorageIconType.offlineSongs) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.orange[400], size: 24),
              const SizedBox(width: 12),
              const Text(
                'Delete Offline Songs?',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: Text(
            'This will delete all downloaded songs. You\'ll need to re-download them for offline playback.',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    setState(() {
      _isClearingStorage = true;
      _clearingCategoryName = category.name;
    });

    try {
      await category.onClear!();
      if (mounted) {
        AppSnackbar.success(context, '${category.name} cleared successfully');
        _loadStorageData(); // Refresh data
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to clear ${category.name}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingStorage = false;
          _clearingCategoryName = null;
        });
      }
    }
  }

  Future<void> _clearAllCaches() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.cleaning_services_rounded,
              color: Colors.orange[400],
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              'Clear All Caches?',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'This will clear image cache, playlist cache, lyrics, and temporary files. '
          'Offline songs will NOT be deleted.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6C63FF),
            ),
            child: const Text('Clear Caches'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClearingStorage = true;
      _clearingCategoryName = 'all caches';
    });

    try {
      await StorageManagementService.instance.clearAllCaches();
      if (mounted) {
        AppSnackbar.success(context, 'All caches cleared successfully');
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to clear caches');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingStorage = false;
          _clearingCategoryName = null;
        });
      }
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.delete_forever_rounded,
              color: Colors.red[400],
              size: 24,
            ),
            const SizedBox(width: 12),
            const Text(
              'Clear All Data?',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          'This will delete ALL local data including offline songs, caches, and import logs. '
          'Your cloud library will not be affected.',
          style: TextStyle(color: Colors.grey[400], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[500])),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isClearingStorage = true;
      _clearingCategoryName = 'all data';
    });

    try {
      await StorageManagementService.instance.clearAllData();
      if (mounted) {
        AppSnackbar.success(context, 'All local data cleared');
        _loadStorageData();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Failed to clear data');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isClearingStorage = false;
          _clearingCategoryName = null;
        });
      }
    }
  }

  Widget _buildStorageContent() {
    // Load storage data if not loaded
    if (_storageCategories == null && !_isLoadingStorage) {
      _loadStorageData();
    }

    if (_isLoadingStorage || _storageCategories == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF6C63FF)),
              const SizedBox(height: 16),
              Text(
                'Analyzing storage...',
                style: TextStyle(color: Colors.grey[500], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final categories = _storageCategories!;
    final totalBytes = categories.fold<int>(0, (sum, cat) => sum + cat.bytes);

    // Format total size
    String totalSize;
    if (totalBytes < 1024 * 1024) {
      totalSize = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else if (totalBytes < 1024 * 1024 * 1024) {
      totalSize = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      totalSize =
          '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 400;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Storage Card
            Container(
              padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A1A1A), Color(0xFF0D0D0D)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  // Header - stacked on mobile, row on desktop
                  if (isSmallScreen) ...[
                    // Mobile: Stacked layout
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.storage_rounded,
                            color: Color(0xFF6C63FF),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Local Storage',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Total used by KioKuu',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          totalSize,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // Desktop: Side-by-side layout
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6C63FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.storage_rounded,
                            color: Color(0xFF6C63FF),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Local Storage',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total used by KioKuu',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          totalSize,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: isSmallScreen ? 16 : 20),

                  // Storage Bar with segments
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: const Color(0xFF2A2A2A),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Row(
                        children: categories.where((c) => c.bytes > 0).map((
                          cat,
                        ) {
                          final percentage = totalBytes > 0
                              ? cat.bytes / totalBytes
                              : 0.0;
                          return Expanded(
                            flex: (percentage * 1000).toInt().clamp(1, 1000),
                            child: Container(
                              color: _getStorageColor(cat.iconType),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Legend
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: categories.where((c) => c.bytes > 0).map((cat) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _getStorageColor(cat.iconType),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat.name,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Storage Categories
            Text(
              'Storage Breakdown',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            ...categories.map(
              (category) => _buildStorageCategoryTile(category),
            ),

            const SizedBox(height: 32),

            // Quick Actions
            Text(
              'Quick Actions',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // Clear All Caches Button
            _buildStorageActionButton(
              icon: Icons.cleaning_services_rounded,
              label: 'Clear All Caches',
              description: 'Free up space without removing offline songs',
              color: const Color(0xFF6C63FF),
              onTap: _isClearingStorage ? null : _clearAllCaches,
              isLoading:
                  _isClearingStorage && _clearingCategoryName == 'all caches',
            ),
            const SizedBox(height: 12),

            // Clear All Data Button
            _buildStorageActionButton(
              icon: Icons.delete_forever_rounded,
              label: 'Clear All Local Data',
              description: 'Delete everything including offline songs',
              color: Colors.red[400]!,
              onTap: _isClearingStorage ? null : _clearAllData,
              isLoading:
                  _isClearingStorage && _clearingCategoryName == 'all data',
            ),

            const SizedBox(height: 24),

            // Info Note
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1F1F1F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.grey[600], size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Your cloud library is stored securely on our servers and won\'t be affected by clearing local data.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStorageCategoryTile(StorageCategory category) {
    final isClearing =
        _isClearingStorage && _clearingCategoryName == category.name;
    final color = _getStorageColor(category.iconType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: category.canClear && category.bytes > 0 && !_isClearingStorage
              ? () => _clearStorageCategory(category)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getStorageIcon(category.iconType),
                    color: color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        category.description,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 11,
                            color: Colors.grey[700],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              category.displayPath,
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontSize: 10,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isClearing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                else ...[
                  Text(
                    category.formattedSize,
                    style: GoogleFonts.inter(
                      color: category.bytes > 0
                          ? Colors.white
                          : Colors.grey[600],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (category.canClear && category.bytes > 0) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.grey[600],
                      size: 18,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStorageActionButton({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: color,
                          ),
                        )
                      : Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color.withOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalStat(
    String value,
    String label,
    IconData icon,
    Color accentColor,
  ) {
    return Container(
      height: 110,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [const Color(0xFF1A1A1A), const Color(0xFF0D0D0D)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Stack(
        children: [
          // Background Icon
          Positioned(
            right: -10,
            bottom: -10,
            child: Icon(icon, size: 80, color: accentColor.withOpacity(0.05)),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        color: Colors.grey[400],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildExtensionsContent() {
    final extensionService = ExtensionRuntimeService.instance;
    final extensions = extensionService.installedExtensions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Installed Extensions'),

        // Extension System Header Card - Compact for mobile
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F6BF6).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.extension,
                    color: Color(0xFF4F6BF6),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Extensions',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Third-party sources',
                        style: TextStyle(color: Colors.grey[500], fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (_isCheckingUpdates)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF4F6BF6),
                      ),
                    ),
                  )
                else
                  IconButton(
                    onPressed: _checkForExtensionUpdates,
                    icon: const Icon(Icons.refresh, size: 20),
                    color: const Color(0xFF4F6BF6),
                    tooltip: 'Check Updates',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _showExtensionDeveloperHelp,
                  icon: const Icon(Icons.help_outline, size: 20),
                  color: Colors.grey[600],
                  tooltip: 'Developer Guide',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: () => _importExtension(extensionService),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F6BF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Import', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Extension List
        if (extensions.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.extension_off_outlined,
                    size: 48,
                    color: Colors.grey[800],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No extensions installed',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Import a .json extension to get started',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _downloadSampleExtension,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Download Sample'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF4F6BF6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...extensions.map(
            (ext) => _buildExtensionTile(extensionService, ext),
          ),
      ],
    );
  }

  Widget _buildExtensionTile(
    ExtensionRuntimeService extensionService,
    ExtensionMetadata ext,
  ) {
    final hasUpdate = _availableUpdates.containsKey(ext.id);
    final newVersion = _availableUpdates[ext.id];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SettingsCard(
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: ext.isEnabled
                      ? const Color(0xFF4F6BF6).withAlpha(30)
                      : Colors.grey.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getExtensionTypeIcon(ext.type),
                  color: ext.isEnabled ? const Color(0xFF4F6BF6) : Colors.grey,
                  size: 24,
                ),
              ),
              title: Row(
                children: [
                  Text(
                    ext.name,
                    style: TextStyle(
                      color: ext.isEnabled ? Colors.white : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'v${ext.version}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 10),
                    ),
                  ),
                  if (hasUpdate) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 16,
                    ),
                  ],
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          ext.author,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ext.description.isNotEmpty
                          ? ext.description
                          : ext.supportedDomains.join(', '),
                      style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              trailing: Switch(
                value: ext.isEnabled,
                onChanged: (value) async {
                  await extensionService.setExtensionEnabled(ext.id, value);
                  setState(() {});
                },
                activeColor: const Color(0xFF4F6BF6),
              ),
            ),
            // Sub-actions area
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                    ),
                    child: InkWell(
                      onTap: hasUpdate
                          ? () => _updateExtension(extensionService, ext.id)
                          : _checkForExtensionUpdates,
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                      ),
                      hoverColor: hasUpdate
                          ? Colors.greenAccent.withOpacity(0.1)
                          : Colors.white.withOpacity(0.05),
                      splashColor: hasUpdate
                          ? Colors.greenAccent.withOpacity(0.2)
                          : Colors.white.withOpacity(0.1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: hasUpdate
                              ? [
                                  const Icon(
                                    Icons.system_update_alt,
                                    size: 16,
                                    color: Colors.greenAccent,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Update to v$newVersion',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ]
                              : [
                                  if (_isCheckingUpdates)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.grey,
                                            ),
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.refresh,
                                      size: 14,
                                      color: Colors.grey,
                                    ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Check Updates',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Colors.white.withOpacity(0.05),
                ),
                Expanded(
                  child: Material(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: const BorderRadius.only(
                      bottomRight: Radius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => _removeExtension(extensionService, ext),
                      borderRadius: const BorderRadius.only(
                        bottomRight: Radius.circular(12),
                      ),
                      hoverColor: Colors.redAccent.withOpacity(0.1),
                      splashColor: Colors.redAccent.withOpacity(0.2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.delete_outline,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Remove',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
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
          ],
        ),
      ),
    );
  }

  Future<void> _checkForExtensionUpdates({bool showSnackbar = true}) async {
    final extensionService = ExtensionRuntimeService.instance;

    // Don't check if no extensions installed
    if (extensionService.installedExtensions.isEmpty) {
      if (showSnackbar) {
        AppSnackbar.error(context, 'No extensions installed');
      }
      return;
    }

    setState(() => _isCheckingUpdates = true);
    final updates = await extensionService.checkForUpdates();
    if (mounted) {
      setState(() {
        _availableUpdates = updates;
        _isCheckingUpdates = false;
      });
      if (showSnackbar) {
        if (updates.isEmpty) {
          AppSnackbar.success(context, 'All extensions are up to date');
        } else {
          AppSnackbar.success(
            context,
            'Found ${updates.length} update${updates.length > 1 ? 's' : ''}',
          );
        }
      }
    }
  }

  Future<void> _updateExtension(
    ExtensionRuntimeService extensionService,
    String id,
  ) async {
    final result = await extensionService.updateExtension(id);
    if (mounted) {
      if (result.success) {
        AppSnackbar.success(
          context,
          '${result.data!.name} updated to v${result.data!.version}',
        );
        setState(() {
          _availableUpdates.remove(id);
        });
      } else {
        AppSnackbar.error(context, 'Update failed: ${result.error}');
      }
    }
  }

  void _showExtensionDeveloperHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.code, color: Color(0xFF4F6BF6), size: 20),
            const SizedBox(width: 8),
            Text(
              'Extension Development',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Metadata Fields:',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              _buildHelpRow('id', 'Unique identifier (string)'),
              _buildHelpRow('name', 'Display name'),
              _buildHelpRow('version', 'Semantic version (e.g. 1.0.1)'),
              _buildHelpRow('updateUrl', 'URL to fetch the latest config JSON'),
              const SizedBox(height: 16),
              Text(
                'Update System:',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'When you release a new version, simply update the "version" field in the JSON hosted at your updateUrl. The app will detect the change and prompt the user to update.',
                style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _downloadSampleExtension();
            },
            icon: const Icon(Icons.download, size: 16),
            label: Text(
              'Download Sample',
              style: GoogleFonts.inter(color: Colors.grey[400]),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: GoogleFonts.inter(color: const Color(0xFF4F6BF6)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadSampleExtension() async {
    try {
      // Load sample extension from bundled assets
      final jsonString = await rootBundle.loadString(
        'assets/extensions/example-extension.json',
      );

      // Get downloads directory
      Directory? downloadsDir;
      if (!kIsWeb && Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else if (!kIsWeb) {
        downloadsDir = await getDownloadsDirectory();
      }

      if (downloadsDir == null) {
        if (mounted) {
          AppSnackbar.error(context, 'Could not access downloads folder');
        }
        return;
      }

      // Save file
      final filePath = '${downloadsDir.path}/sample-extension.json';
      final file = File(filePath);
      await file.writeAsString(jsonString);

      if (mounted) {
        AppSnackbar.show(
          context,
          message: 'Sample saved to Downloads',
          icon: Icons.download_done,
          actionLabel: 'Open',
          onAction: () async {
            // Try to open the file
            final uri = Uri.file(filePath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
            } else if (!kIsWeb && Platform.isAndroid) {
              // Fallback: open downloads folder
              await launchUrl(
                Uri.parse(
                  'content://com.android.externalstorage.documents/document/primary:Download',
                ),
                mode: LaunchMode.externalApplication,
              );
            }
          },
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error: $e');
      }
    }
  }

  Widget _buildHelpRow(String key, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$key: ',
            style: GoogleFonts.robotoMono(
              color: Colors.blueAccent,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: GoogleFonts.inter(color: Colors.grey[400], fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _importExtension(
    ExtensionRuntimeService extensionService,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Extension File',
      );

      if (result != null && result.files.single.path != null) {
        final importResult = await extensionService.importExtension(
          result.files.single.path!,
        );

        if (mounted) {
          if (importResult.success) {
            AppSnackbar.success(
              context,
              'Extension "${importResult.data!.name}" imported successfully',
            );
            setState(() {}); // Refresh the list
          } else {
            AppSnackbar.error(
              context,
              'Failed to import: ${importResult.error}',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.error(context, 'Error: $e');
      }
    }
  }

  Future<void> _removeExtension(
    ExtensionRuntimeService extensionService,
    ExtensionMetadata extension,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Remove Extension',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to remove "${extension.name}"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await extensionService.removeExtension(extension.id);
      if (mounted) {
        AppSnackbar.success(context, 'Extension removed');
        setState(() {});
      }
    }
  }

  IconData _getExtensionTypeIcon(ExtensionType type) {
    switch (type) {
      case ExtensionType.scraper:
        return Icons.search;
      case ExtensionType.downloader:
        return Icons.download;
      case ExtensionType.full:
        return Icons.extension;
    }
  }

  Widget _buildAutoImportContent() {
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final hasCustomFolder =
        _importFolderPath != null &&
        !_importFolderPath!.contains('Android/data/');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Watched Folder'),

        // Android-specific guidance card
        if (isAndroid && !hasCustomFolder) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4F6BF6).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF4F6BF6).withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.folder_special,
                      color: Color(0xFF4F6BF6),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Select Your Music Folder',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose a folder where you\'ll drop music files for auto-import. '
                  'This can be your Downloads folder, Music folder, or any folder you prefer.',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _pickImportFolder,
                    icon: const Icon(Icons.folder_open, size: 20),
                    label: const Text('Choose Folder'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F6BF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

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
                  _importFolderPath ?? 'No folder selected',
                  style: TextStyle(
                    color: hasCustomFolder || !isAndroid
                        ? Colors.grey[400]
                        : Colors.orange,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.folder_open,
                        color: Colors.white70,
                      ),
                      onPressed: _pickImportFolder,
                      tooltip: 'Change folder',
                    ),
                    if (!isAndroid) // Only show reset on non-Android
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        onPressed: _resetToDefaultFolder,
                        tooltip: 'Reset to default',
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            isAndroid
                                ? 'Select any folder on your device. Music files added there will be auto-imported.'
                                : 'Audio files dropped here will be processed automatically.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickImportFolder,
                            icon: const Icon(Icons.folder, size: 18),
                            label: const Text('Change Folder'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(
                                color: Colors.grey.withOpacity(0.3),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        if (!isAndroid) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _resetToDefaultFolder,
                              icon: const Icon(Icons.restore, size: 18),
                              label: const Text('Reset Default'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.orange,
                                side: BorderSide(
                                  color: Colors.orange.withOpacity(0.3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
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
    final allTasks = ImportProcessorService.instance.tasks;

    // Categorize tasks by status
    final uploadingTasks = allTasks
        .where((t) => t.status == ImportStatus.uploading)
        .toList();
    final processingTasks = allTasks
        .where(
          (t) =>
              t.status == ImportStatus.pending ||
              t.status == ImportStatus.extractingMetadata ||
              t.status == ImportStatus.matchingWithAI ||
              t.status == ImportStatus.waitingForAI,
        )
        .toList();
    final reviewTasks = allTasks
        .where((t) => t.status == ImportStatus.awaitingReview)
        .toList();
    final completedTasks = allTasks
        .where((t) => t.status == ImportStatus.completed)
        .toList();
    final failedTasks = allTasks
        .where((t) => t.status == ImportStatus.failed)
        .toList();

    final hasAnyTasks = allTasks.isNotEmpty;

    if (!hasAnyTasks) {
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
              'No import tasks',
              style: TextStyle(color: Colors.grey[500], fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Uploading section
        if (uploadingTasks.isNotEmpty) ...[
          _SectionHeader('Uploading'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withAlpha(50)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${uploadingTasks.length} file${uploadingTasks.length > 1 ? 's' : ''} uploading',
                    style: const TextStyle(color: Colors.blue, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...uploadingTasks.map((task) => _buildUploadingTaskCard(task)),
          const SizedBox(height: 24),
        ],

        // Processing queue section
        if (processingTasks.isNotEmpty) ...[
          _SectionHeader('Processing Queue'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(20),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withAlpha(50)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${processingTasks.length} file${processingTasks.length > 1 ? 's' : ''} in queue',
                    style: const TextStyle(color: Colors.orange, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...processingTasks.map((task) => _buildProcessingTaskCard(task)),
          const SizedBox(height: 24),
        ],

        // Awaiting review section
        if (reviewTasks.isNotEmpty) ...[
          _SectionHeader('Awaiting Review'),
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
          const SizedBox(height: 16),
          ...reviewTasks.map((task) => _buildReviewTaskCard(task)),
          const SizedBox(height: 24),
        ],

        // Completed section
        if (completedTasks.isNotEmpty) ...[
          _SectionHeader('Recently Completed'),
          ...completedTasks.map((task) => _buildCompletedTaskCard(task)),
          const SizedBox(height: 24),
        ],

        // Failed section
        if (failedTasks.isNotEmpty) ...[
          _SectionHeader('Failed'),
          ...failedTasks.map((task) => _buildFailedTaskCard(task)),
          const SizedBox(height: 24),
        ],

        // Clear completed button
        if (completedTasks.isNotEmpty || failedTasks.isNotEmpty)
          Center(
            child: TextButton.icon(
              onPressed: () {
                ImportProcessorService.instance.clearCompletedTasks();
                setState(() {});
              },
              icon: const Icon(Icons.clear_all, size: 18),
              label: const Text('Clear Completed'),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
            ),
          ),
      ],
    );
  }

  Widget _buildUploadingTaskCard(ImportTask task) {
    final albumArt = task.aiMatchResult?.albumArt;
    final progress = task.uploadProgress;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _SettingsCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Album art
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: albumArt != null && albumArt.isNotEmpty
                        ? Image.network(
                            albumArt,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(48),
                          )
                        : _buildPlaceholder(48),
                  ),
                  const SizedBox(width: 12),
                  // Song info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title ?? task.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.artist ?? 'Unknown artist',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Progress percentage
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withAlpha(20),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingTaskCard(ImportTask task) {
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (task.status) {
      case ImportStatus.pending:
        statusText = 'Queued';
        statusIcon = Icons.schedule;
        statusColor = Colors.grey;
        break;
      case ImportStatus.waitingForAI:
        statusText = 'Waiting for AI';
        statusIcon = Icons.smart_toy;
        statusColor = Colors.orange;
        break;
      case ImportStatus.extractingMetadata:
        statusText = 'Reading metadata';
        statusIcon = Icons.library_music;
        statusColor = Colors.purple;
        break;
      case ImportStatus.matchingWithAI:
        statusText = 'AI matching...';
        statusIcon = Icons.auto_awesome;
        statusColor = const Color(0xFFE040FB);
        break;
      default:
        statusText = 'Processing';
        statusIcon = Icons.sync;
        statusColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _SettingsCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          title: Text(
            task.title ?? task.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            statusText,
            style: TextStyle(color: statusColor, fontSize: 12),
          ),
          trailing:
              task.status == ImportStatus.matchingWithAI ||
                  task.status == ImportStatus.extractingMetadata
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildCompletedTaskCard(ImportTask task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _SettingsCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 20,
            ),
          ),
          title: Text(
            task.title ?? task.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            task.artist ?? 'Uploaded successfully',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.check, color: Colors.green, size: 20),
        ),
      ),
    );
  }

  Widget _buildFailedTaskCard(ImportTask task) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _SettingsCard(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.red.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 20,
            ),
          ),
          title: Text(
            task.title ?? task.fileName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            task.errorMessage ?? 'Upload failed',
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
            onPressed: () {
              task.status = ImportStatus.pending;
              task.errorMessage = null;
              task.uploadProgress = 0.0;
              ImportProcessorService.instance.retryFailedTasks();
              setState(() {});
            },
            tooltip: 'Retry',
          ),
        ),
      ),
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
          Icon(
            ExtensionManagerService.instance.isEnabled(extensionId)
                ? Icons.cloud_done
                : Icons.cloud_off,
            size: 18,
            color: ExtensionManagerService.instance.isEnabled(extensionId)
                ? Colors.white
                : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ExtensionManagerService.instance.isEnabled(extensionId)
                      ? 'Cloud AI Active'
                      : 'Cloud AI Disabled',
                  style: const TextStyle(
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
          const SizedBox(width: 8),
          Switch(
            value: ExtensionManagerService.instance.isEnabled(extensionId),
            onChanged: (value) async {
              await ExtensionManagerService.instance.setEnabled(
                extensionId,
                value,
              );
              if (value) {
                // If enabled, trigger a scan of the import folder
                ImportWatcherService.instance.checkExistingFiles();
              }
              setState(() {});
            },
            activeColor: Colors.white,
            activeTrackColor: Colors.white.withOpacity(0.5),
            inactiveThumbColor: Colors.grey[400],
            inactiveTrackColor: Colors.grey[800],
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
            leading: _isLoggingOut
                ? LoadingAnimationWidget.threeArchedCircle(
                    color: Colors.redAccent,
                    size: 24,
                  )
                : const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Log Out', style: TextStyle(color: Colors.white)),
            subtitle: const Text(
              'Sign out of your account on this device',
              style: TextStyle(color: Colors.grey),
            ),
            onTap: _isLoggingOut ? null : _logout,
          ),
        ),
      ],
    );
  }

  // Discord RPC state
  bool _isDiscordRpcEnabled = false;
  bool _isDiscordRpcConnected = false;

  void _initDiscordRpcState() {
    _isDiscordRpcEnabled = DiscordRpcService.instance.isEnabled;
    _isDiscordRpcConnected = DiscordRpcService.instance.isConnected;
  }

  Widget _buildConnectionsContent() {
    // Initialize state on first build
    if (!_isDiscordRpcEnabled && DiscordRpcService.instance.isEnabled) {
      _initDiscordRpcState();
    }

    final isDesktop = !kIsWeb && !Platform.isAndroid && !Platform.isIOS;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader('Discord'),
        _SettingsCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Discord logo
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5865F2).withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.discord,
                        color: Color(0xFF5865F2),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Discord Rich Presence',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Show what you\'re listening to on Discord',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isDesktop) ...[
                      // Status indicator
                      if (_isDiscordRpcEnabled)
                        Container(
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isDiscordRpcConnected
                                ? Colors.green.withAlpha(30)
                                : Colors.orange.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: _isDiscordRpcConnected
                                      ? Colors.green
                                      : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _isDiscordRpcConnected
                                    ? 'Connected'
                                    : 'Connecting...',
                                style: TextStyle(
                                  color: _isDiscordRpcConnected
                                      ? Colors.green
                                      : Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Switch(
                        value: _isDiscordRpcEnabled,
                        activeColor: const Color(0xFF5865F2),
                        onChanged: (enabled) async {
                          if (enabled) {
                            await DiscordRpcService.instance.enable();
                          } else {
                            await DiscordRpcService.instance.disable();
                          }
                          setState(() {
                            _isDiscordRpcEnabled =
                                DiscordRpcService.instance.isEnabled;
                            _isDiscordRpcConnected =
                                DiscordRpcService.instance.isConnected;
                          });
                        },
                      ),
                    ] else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Desktop only',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                if (isDesktop && _isDiscordRpcEnabled) ...[
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 16),
                  // Preview section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.grey,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your current song will appear in your Discord status when playing music.',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),

        // Info about more connections coming
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.add_link, color: Colors.grey[600], size: 40),
                const SizedBox(height: 12),
                Text(
                  'More connections coming soon',
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Spotify, Last.fm, and more',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAboutContent() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Card
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            vertical: isSmallScreen ? 32 : 48,
            horizontal: isSmallScreen ? 16 : 24,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isSmallScreen ? 16 : 24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xFF7B68EE).withOpacity(0.15), Colors.black],
            ),
            border: Border.all(
              color: const Color(0xFF7B68EE).withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo with Glow
              Container(
                width: isSmallScreen ? 80 : 100,
                height: isSmallScreen ? 80 : 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7B68EE).withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/images/kiokuu_white.svg',
                    width: isSmallScreen ? 40 : 50,
                    height: isSmallScreen ? 40 : 50,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
              SizedBox(height: isSmallScreen ? 16 : 24),
              // App Title
              Text(
                'KioKuu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isSmallScreen ? 28 : 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              // Version Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Text(
                  'v$_appVersion Beta',
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'A Place to store your music',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: isSmallScreen ? 13 : 14,
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        SizedBox(height: isSmallScreen ? 24 : 32),

        _SectionHeader('Connect'),

        // Responsive grid - 2 columns on desktop, 1 column on mobile
        if (isSmallScreen) ...[
          SizedBox(
            width: double.infinity,
            child: _buildConnectCardMobile(
              icon: Icons.language,
              title: 'Website',
              subtitle: 'kiokuu.app',
              onTap: () => launchUrl(Uri.parse(AppConfig.websiteUrl)),
              color: Colors.blueAccent,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _buildConnectCardMobile(
              icon: Icons.code,
              title: 'GitHub',
              subtitle: 'Source Code',
              onTap: () => launchUrl(
                Uri.parse(
                  'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}',
                ),
              ),
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _buildConnectCardMobile(
              icon: Icons.discord,
              title: 'Discord',
              subtitle: 'Join Community',
              onTap: () => launchUrl(Uri.parse(AppConfig.discordInviteUrl)),
              color: const Color(0xFF5865F2),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: _buildConnectCardMobile(
              icon: Icons.bug_report_outlined,
              title: 'Report Issue',
              subtitle: 'Help us improve',
              onTap: () => launchUrl(
                Uri.parse(
                  'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}/issues',
                ),
              ),
              color: Colors.amber,
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _buildConnectCard(
                  icon: Icons.language,
                  title: 'Website',
                  subtitle: 'kiokuu.app',
                  onTap: () => launchUrl(Uri.parse(AppConfig.websiteUrl)),
                  color: Colors.blueAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildConnectCard(
                  icon: Icons.code,
                  title: 'GitHub',
                  subtitle: 'Source Code',
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}',
                    ),
                  ),
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildConnectCard(
                  icon: Icons.discord,
                  title: 'Discord',
                  subtitle: 'Join Community',
                  onTap: () => launchUrl(Uri.parse(AppConfig.discordInviteUrl)),
                  color: const Color(0xFF5865F2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildConnectCard(
                  icon: Icons.bug_report_outlined,
                  title: 'Report Issue',
                  subtitle: 'Help us improve',
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}/issues',
                    ),
                  ),
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ],

        SizedBox(height: isSmallScreen ? 24 : 32),

        _SectionHeader('Legal'),
        _SettingsCard(
          child: Column(
            children: [
              _buildLegalTile(
                'Privacy Policy',
                onTap: () => launchUrl(
                  Uri.parse(
                    '${AppConfig.apiBaseUrl.replaceAll('api.', '')}/privacy',
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              _buildLegalTile(
                'Terms of Service',
                onTap: () => launchUrl(
                  Uri.parse(
                    '${AppConfig.apiBaseUrl.replaceAll('api.', '')}/terms',
                  ),
                ),
              ),
              const Divider(height: 1, color: Colors.white12),
              _buildLegalTile(
                'Open Source Licenses',
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'KioKuu',
                  applicationVersion: _appVersion,
                  applicationIcon: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SvgPicture.asset(
                      'assets/images/kiokuu_white.svg',
                      width: 48,
                      height: 48,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        SizedBox(height: isSmallScreen ? 32 : 48),
        Center(
          child: Opacity(
            opacity: 0.5,
            child: Column(
              children: [
                const Icon(Icons.favorite, size: 16, color: Colors.redAccent),
                const SizedBox(height: 8),
                Text(
                  'Made with ♥ by KioKuu Team',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildConnectCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Mobile version - horizontal layout for compact display
  Widget _buildConnectCardMobile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[600], size: 14),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalTile(String title, {required VoidCallback onTap}) {
    return ListTile(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: Colors.grey[600],
        size: 14,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _loadUsername();
    _loadVersion();
  }

  Future<void> _loadUsername() async {
    final username = await ApiService().username;
    if (mounted) {
      setState(() {
        _username = username ?? 'Unknown';
      });
    }
  }

  Future<void> _loadVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
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
          _StatRow('Client Version', _version),
          const SizedBox(height: 6),
          _StatRow('Platform', kIsWeb ? 'Web' : Platform.operatingSystem),
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
