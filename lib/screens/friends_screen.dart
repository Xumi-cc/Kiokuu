import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // UwU fonts
import '../services/friends_service.dart';
import '../services/websocket_service.dart' as ws;

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> with TickerProviderStateMixin {
  final _friendsService = FriendsService();
  final _wsService = ws.WebSocketService();
  
  // Data
  List<Friend> _friends = [];
  List<FriendRequest> _requests = [];
  Map<String, ws.FriendActivity> _friendActivities = {};
  
  // State
  bool _isLoading = true;
  final TransformationController _transformController = TransformationController();
  
  // Constellation State
  // We'll map friend IDs to a fixed position in the "universe"
  // coordinate system: -2000 to +2000 on both axes
  final Map<String, Offset> _friendPositions = {};
  
  // Stars (Animated background)
  final List<Offset> _stars = [];
  final List<double> _starSizes = [];
  final List<double> _starOpacities = [];
  final List<double> _starTwinkleSpeeds = []; // Unique twinkle rate per star
  late AnimationController _starAnimController;
  
  // Interpolation (same smooth time logic as before)
  Timer? _interpolationTimer;
  Map<String, int> _baselineTimestamp = {};
  
  // WebSocket subscriptions (to cancel in dispose)
  StreamSubscription? _activityUpdateSub;
  StreamSubscription? _friendsActivitySub;
  StreamSubscription? _friendOnlineSub;
  Map<String, int> _baselinePosition = {};

  @override
  void initState() {
    super.initState();
    _starAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10), // Full cycle
    )..repeat();
    _generateStars();
    _loadData();
    _setupWebSocket();
    _startTimer();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerView();
    });
  }

  void _generateStars() {
    final rng = Random(1337);
    for (int i = 0; i < 2000; i++) {
      _stars.add(Offset(rng.nextDouble() * 5000, rng.nextDouble() * 5000));
      _starSizes.add(rng.nextDouble() * 1.5 + 0.5);
      _starOpacities.add(rng.nextDouble() * 0.6 + 0.2); // Base opacity
      _starTwinkleSpeeds.add(rng.nextDouble() * 3.0 + 1.0); // 1-4 cycles per animation
    }
  }

  void _centerView() {
    // 5000x5000 canvas. Center is at 2500, 2500.
    // Screen center needs to align with Canvas center.
    if (!mounted) return;
    final size = MediaQuery.of(context).size;
    final x = -2500.0 + size.width / 2;
    final y = -2500.0 + size.height / 2;
    _transformController.value = Matrix4.identity()..translate(x, y);
  }

  @override
  void dispose() {
    _interpolationTimer?.cancel();
    _activityUpdateSub?.cancel();
    _friendsActivitySub?.cancel();
    _friendOnlineSub?.cancel();
    _starAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _interpolationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_friendActivities.values.any((a) => a.isPlaying)) {
        setState(() {}); // Trigger repaint for time updates
      }
    });
  }

  // --- Data Loading & WebSocket ---
  
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final friends = await _friendsService.getFriends();
      final requests = await _friendsService.getFriendRequests();
      
      if (mounted) {
        setState(() {
          _friends = friends;
          _requests = requests;
          _isLoading = false;
          _generatePositions();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _generatePositions() {
    _friendPositions.clear();
    
    for (var friend in _friends) {
      // Create a deterministic random position based on their unique ID
      final seed = friend.id.codeUnits.fold(0, (p, c) => p + c);
      final r = Random(seed);
      
      // Random angle
      final theta = r.nextDouble() * 2 * pi;
      // Random distance (scattered but not too far, mostly towards center)
      // Radius between 200 and 1500
      final radius = 200.0 + r.nextDouble() * 1000.0;
      
      final x = 2500 + radius * cos(theta);
      final y = 2500 + radius * sin(theta);
      
      _friendPositions[friend.id] = Offset(x, y);
    }
  }

  void _setupWebSocket() {
    if (!_wsService.isConnected) _wsService.connect();

    _activityUpdateSub = _wsService.onActivityUpdate.listen((activity) {
      if (mounted) setState(() {
        final now = DateTime.now().millisecondsSinceEpoch;
        final friendId = activity.userId;

        // Only keep new baseline if progress < 2 seconds (start of song)
        // or if different song.
        if ((activity.positionMs ?? 0) < 2000 || _friendActivities[friendId]?.songId != activity.songId) {
           _baselineTimestamp[friendId] = now;
           _baselinePosition[friendId] = activity.positionMs ?? 0;
        }
        
        _friendActivities[friendId] = activity;
      });
    }, onError: (e) => debugPrint('WebSowket Ewwow: $e'));

    _friendsActivitySub = _wsService.onFriendsActivity.listen((activities) {
      if (mounted) setState(() {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (var a in activities) {
          final friendId = a.userId;
          // Only keep new baseline if progress < 2 seconds (start of song)
          // or if different song.
          if ((a.positionMs ?? 0) < 2000 || _friendActivities[friendId]?.songId != a.songId) {
             _baselineTimestamp[friendId] = now;
             _baselinePosition[friendId] = a.positionMs ?? 0;
          }
          _friendActivities[friendId] = a;
        }
      });
    }, onError: (e) => debugPrint('WebSowket Ewwow: $e'));
    
    _friendOnlineSub = _wsService.onFriendOnline.listen((_) => _loadData());
  }
  
  // Time Helpers
  int _getInterpolatedPosition(String id) {
    if (!_baselineTimestamp.containsKey(id)) return 0;
    final diff = DateTime.now().millisecondsSinceEpoch - (_baselineTimestamp[id] ?? 0);
    return (_baselinePosition[id] ?? 0) + diff;
  }
  
  String _formatTime(int ms) {
    if (ms <= 0) return "--:--";
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  // --- UI Construction ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050505), // Match star field
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchDialog,
        backgroundColor: Colors.white,
        child: const Icon(Icons.person_add, color: Colors.black),
      ),
      body: Stack(
        children: [
          // 1. The Interactive Universe
          _buildUniverse(),
          
          // 2. UI Overlays (Header, Search, Requests)
          _buildHud(),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _SearchDialog(friendsService: _friendsService),
    ).then((_) => _loadData()); 
  }

  void _showQuickJumpDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Text('Jump to Friend', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
                child: Center(
                  child: Column(
                    children: [
                      const Text('(っ◞‸◟c)', style: TextStyle(fontSize: 32, color: Colors.white54)),
                      const SizedBox(height: 12),
                      Text(
                        "Such empty, much lonely",
                        style: TextStyle(color: Colors.grey[500], fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Add some friends to see them here!",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _friends.length,
                  itemBuilder: (_, i) {
                    final friend = _friends[i];
                    final activity = _friendActivities[friend.id];
                    final isOnline = activity != null && activity.songId != null;
                    
                    return ListTile(
                      leading: Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: friend.photoUrl.isNotEmpty ? NetworkImage(friend.photoUrl) : null,
                            backgroundColor: const Color(0xFF333333),
                            child: friend.photoUrl.isEmpty ? Text(friend.username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) : null,
                          ),
                          if (isOnline)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF1A1A1A), width: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                      title: Text(friend.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      subtitle: isOnline
                        ? Row(
                            children: [
                              const Icon(Icons.music_note, size: 12, color: Colors.green),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${activity!.songTitle ?? "Unknown"} - ${activity.artistName ?? "Unknown"}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : const Text('Offline', style: TextStyle(color: Colors.white30, fontSize: 12)),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                      onTap: () {
                        Navigator.pop(ctx);
                        _panToFriend(friend.id);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _panToFriend(String friendId) {
    final pos = _friendPositions[friendId];
    if (pos == null) return;
    
    final size = MediaQuery.of(context).size;
    final Matrix4 matrix = Matrix4.identity()
      ..translate(-pos.dx + size.width / 2, -pos.dy + size.height / 2);
    
    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    final animation = Matrix4Tween(
      begin: _transformController.value,
      end: matrix,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic));
    
    animation.addListener(() => _transformController.value = animation.value);
  }

  Future<void> _unfriend(Friend friend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _GlassThemeDialog(
        title: 'Unfwiend Request? 🥺',
        content: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.heart_broken_rounded, size: 32, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Text(
              'Aww yuu suwe yuu want to unfwiend ${friend.username}? They will dwift away...',
              textAlign: TextAlign.center,
              style: GoogleFonts.mPlusRounded1c(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Nu, Keep!', style: GoogleFonts.mPlusRounded1c(color: Colors.white54, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.person_remove_rounded, size: 18),
            label: Text('Unfwiend', style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
      );
      
      final success = await _friendsService.removeFriend(friend.id);
      
      if (mounted) Navigator.pop(context); // Close loading
      
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_off, color: Colors.white),
                const SizedBox(width: 12),
                Text('${friend.username} has dwifted away...', style: GoogleFonts.mPlusRounded1c()),
              ],
            ),
            backgroundColor: const Color(0xFF282828),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _loadData();
      }
    }
  }

  Future<void> _acceptRequest(FriendRequest request) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
    );
    
    final success = await _friendsService.acceptFriendRequest(request.id);
    
    if (mounted) Navigator.pop(context); // Close loading
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
             children: [
               const Icon(Icons.check_circle_rounded, color: Colors.black),
               const SizedBox(width: 12),
               Text('${request.fromUser.username} entered yuw owbit!', style: GoogleFonts.mPlusRounded1c(color: Colors.black)),
             ],
          ),
          backgroundColor: Colors.white,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      _loadData();
    }
  }

  Future<void> _rejectRequest(FriendRequest request) async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white70)),
    );
    
    final success = await _friendsService.rejectFriendRequest(request.id);
    
    if (mounted) Navigator.pop(context); // Close loading
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${request.fromUser.username}\'s meteow buwned up...', style: GoogleFonts.mPlusRounded1c())),
      );
      _loadData();
    }
  }

  Widget _buildUniverse() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return InteractiveViewer(
      transformationController: _transformController,
      boundaryMargin: EdgeInsets.zero, // No scrolling past edges
      minScale: 0.4,
      maxScale: 4.0,
      constrained: false, // Infinite canvas
      child: Container(
        width: 5000,
        height: 5000,
        color: const Color(0xFF050505), // Deep space black
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Animated Background Stars
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _starAnimController,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AnimatedStarPainter(
                      stars: _stars,
                      sizes: _starSizes,
                      baseOpacities: _starOpacities,
                      twinkleSpeeds: _starTwinkleSpeeds,
                      animValue: _starAnimController.value,
                    ),
                  );
                },
              ),
            ),
            
            // Friends aka "Space Nodes"
            ..._friends.map((friend) {
              final pos = _friendPositions[friend.id] ?? const Offset(2500, 2500);
              final activity = _friendActivities[friend.id];
              return Positioned(
                left: pos.dx - 60, // Center the nodes
                top: pos.dy - 60,
                child: _FriendPlanetNode(
                  friend: friend,
                  activity: activity,
                  interpolatedPosition: activity?.isPlaying == true 
                      ? _getInterpolatedPosition(friend.id) 
                      : 0,
                  formattedTime: _formatTime(
                    activity?.isPlaying == true ? _getInterpolatedPosition(friend.id) : 0
                  ),
                  onUnfriend: () => _unfriend(friend),
                ),
              );
            }),
            
            // Friend Requests as Meteors streaking through space!
            ..._requests.asMap().entries.map((entry) {
              final index = entry.key;
              final request = entry.value;
              return _MeteorRequest(
                key: ValueKey(request.id),
                request: request,
                index: index,
                onAccept: () => _acceptRequest(request),
                onReject: () => _rejectRequest(request),
              );
            }),
            
            // "You" are the center of the universe (literally)
            const Positioned(
              left: 2500 - 40,
              top: 2500 - 40,
              child: _UserSunNode(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHud() {
    return SafeArea(
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Builder(
                    builder: (context) {
                      final screenWidth = MediaQuery.of(context).size.width;
                      final titleSize = screenWidth < 360 ? 16.0 : (screenWidth < 600 ? 18.0 : 20.0);
                      return Text(
                        'Fwiends Universe',
                        style: GoogleFonts.mPlusRounded1c(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: titleSize,
                          letterSpacing: -0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ),
                // Quick Jump to Friend
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white70),
                  onPressed: _showQuickJumpDialog,
                ),
                // Recenter Button
                IconButton(
                  icon: const Icon(Icons.my_location, color: Colors.white70),
                  onPressed: () {
                     final size = MediaQuery.of(context).size;
                     final Matrix4 matrix = Matrix4.identity()
                       ..translate(-2500.0 + size.width / 2, -2500.0 + size.height / 2);
                     
                     final animation = Matrix4Tween(
                       begin: _transformController.value,
                       end: matrix,
                     ).animate(CurvedAnimation(
                       parent: AnimationController(
                         vsync: this, 
                         duration: const Duration(milliseconds: 600)
                       )..forward(),
                       curve: Curves.easeInOutBack,
                     ));
                     
                     animation.addListener(() {
                       _transformController.value = animation.value;
                     });
                  },
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Friend Request Mini-HUD (Bottom Left)
          if (_requests.isNotEmpty)
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.5)),
                  boxShadow: [
                     BoxShadow(color: Colors.white.withOpacity(0.2), blurRadius: 10),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mail_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_requests.length} New Fwiends!',
                      style: GoogleFonts.mPlusRounded1c(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Component: Search Dialog
// -----------------------------------------------------------------------------

class _SearchDialog extends StatefulWidget {
  final FriendsService friendsService;
  const _SearchDialog({required this.friendsService});

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String _query = '';
  SearchUserResult? _result;
  bool _searching = false;
  bool _sendingRequest = false; // Loading state for send button
  String? _error;

  Future<void> _search() async {
    if (_query.isEmpty) return;
    setState(() { _searching = true; _error = null; _result = null; });
    try {
      final res = await widget.friendsService.searchUser(_query);
      if (mounted) setState(() { _result = res; _searching = false; if(res==null) _error='Not found'; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _searching = false; });
    }
  }

  // Status helper methods
  Color _getStatusColor(String status) {
    switch (status) {
      case 'friends': return Colors.white;
      case 'request_sent': return Colors.white70;
      case 'request_received': return Colors.white;
      case 'previously_friends': return Colors.white38;
      case 'rejected': return Colors.white54;
      default: return Colors.white;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'friends': return Icons.check_circle_rounded;
      case 'request_sent': return Icons.hourglass_top_rounded;
      case 'request_received': return Icons.mail_rounded;
      case 'previously_friends': return Icons.block_rounded;
      case 'rejected': return Icons.refresh_rounded;
      default: return Icons.person_add_rounded;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'friends': return 'Alweady fwiends!';
      case 'request_sent': return 'Wequest pending...';
      case 'request_received': return 'They want to be youw fwiend!';
      case 'previously_friends': return 'Pweviously fwiends';
      case 'rejected': return 'Wejected befowe, twy again?';
      default: return 'Send fwiend wequest!';
    }
  }

  bool _canSendRequest(String status) {
    // Can send if: none (new), rejected (retry allowed)
    return status == 'none' || status == 'rejected';
  }

  @override
  Widget build(BuildContext context) {
    return _GlassThemeDialog(
      title: 'Hunt Fuw Fwiends!',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(15),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              style: GoogleFonts.mPlusRounded1c(color: Colors.white, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                icon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.5)),
                hintText: 'Entew usewname...',
                hintStyle: GoogleFonts.mPlusRounded1c(color: Colors.white.withOpacity(0.3)),
                border: InputBorder.none,
              ),
              onChanged: (v) => _query = v,
              onSubmitted: (_) => _search(),
            ),
          ),
          const SizedBox(height: 20),
          if (_searching) 
            const SizedBox(
              height: 40, 
              child: Center(child: CircularProgressIndicator(color: Colors.white))
            ),
          if (_error != null) 
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!, 
                      style: GoogleFonts.mPlusRounded1c(color: Colors.white70, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_result != null)
             Container(
               margin: const EdgeInsets.only(top: 10),
               decoration: BoxDecoration(
                 color: _getStatusColor(_result!.status).withOpacity(0.1),
                 borderRadius: BorderRadius.circular(15),
                 border: Border.all(color: _getStatusColor(_result!.status).withOpacity(0.3)),
               ),
               child: ListTile(
                leading: CircleAvatar(
                  backgroundImage: _result!.user.photoUrl.isNotEmpty ? NetworkImage(_result!.user.photoUrl) : null,
                  backgroundColor: Colors.white,
                  child: _result!.user.photoUrl.isEmpty ? Text(_result!.user.username[0].toUpperCase(), style: GoogleFonts.mPlusRounded1c(color: Colors.black, fontWeight: FontWeight.bold)) : null,
                ),
                title: Text(_result!.user.username, style: GoogleFonts.mPlusRounded1c(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  _getStatusText(_result!.status),
                  style: GoogleFonts.mPlusRounded1c(color: _getStatusColor(_result!.status), fontSize: 12),
                ),
                trailing: _sendingRequest 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : IconButton(
                      icon: Icon(
                        _getStatusIcon(_result!.status),
                        color: _getStatusColor(_result!.status),
                      ),
                      onPressed: _canSendRequest(_result!.status) ? () async {
                        setState(() => _sendingRequest = true);
                        try {
                          await widget.friendsService.sendFriendRequest(_result!.user.id);
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(children: [const Icon(Icons.send_rounded, color: Colors.white), const SizedBox(width: 10), Text('Wequest sent!', style: GoogleFonts.mPlusRounded1c())]),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              )
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setState(() {
                              _sendingRequest = false;
                              _error = e.toString().replaceAll('ApiException', 'Ewwow');
                            });
                          }
                        }
                      } : null,
                    ),
               ),
             ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: Text('Close', style: GoogleFonts.mPlusRounded1c(color: Colors.white54, fontWeight: FontWeight.bold))
        ),
        ElevatedButton.icon(
          onPressed: _search, 
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 10,
            shadowColor: Colors.white.withOpacity(0.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.search_rounded, size: 18),
          label: Text('Seawch', style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Component: Friend Planet Node
// -----------------------------------------------------------------------------

class _FriendPlanetNode extends StatefulWidget {
  final Friend friend;
  final ws.FriendActivity? activity;
  final int interpolatedPosition;
  final String formattedTime;
  final VoidCallback? onUnfriend;

  const _FriendPlanetNode({
    required this.friend,
    this.activity,
    required this.interpolatedPosition,
    required this.formattedTime,
    this.onUnfriend,
  });

  @override
  State<_FriendPlanetNode> createState() => _FriendPlanetNodeState();
}

class _FriendPlanetNodeState extends State<_FriendPlanetNode> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    // Random float animation to make them look alive in space
    _floatController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 3000 + Random().nextInt(2000)),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.activity?.isPlaying ?? false;
    
    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        // Subtle Bobbing Effect
        final offset = sin(_floatController.value * 2 * pi) * 10;
        return Transform.translate(
          offset: Offset(0, offset),
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        onLongPress: widget.onUnfriend,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          width: _isExpanded ? 280 : 80,
          height: _isExpanded ? 100 : 80,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
             color: _isExpanded ? const Color(0xFF181818).withOpacity(0.95) : Colors.transparent,
             borderRadius: BorderRadius.circular(_isExpanded ? 20 : 40),
             border: _isExpanded ? Border.all(color: Colors.white10) : null,
             boxShadow: _isExpanded ? [
               const BoxShadow(color: Colors.black54, blurRadius: 20, spreadRadius: 5),
             ] : const [], // Empty list instead of null
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Blurred Album Art Background (only when expanded and playing)
              if (_isExpanded && isLive && widget.activity?.albumCover != null)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                          child: Image.network(
                            widget.activity!.albumCover!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(),
                          ),
                        ),
                        // Dark overlay
                        Container(color: Colors.black.withOpacity(0.5)),
                      ],
                    ),
                  ),
                ),
              
              // 1. The Planet (Avatar)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutBack,
                left: _isExpanded ? 10 : 0, 
                child: Container(
                  width: _isExpanded ? 70 : 80,
                  height: _isExpanded ? 70 : 80,
                  alignment: Alignment.center,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Progress Ring (like mobile home screen)
                      if (isLive && (widget.activity?.progress ?? 0) > 0)
                        SizedBox(
                          width: _isExpanded ? 66 : 76,
                          height: _isExpanded ? 66 : 76,
                          child: CircularProgressIndicator(
                            value: widget.activity!.progress.clamp(0.0, 1.0),
                            strokeWidth: 2.5,
                            backgroundColor: Colors.white10,
                            valueColor: const AlwaysStoppedAnimation(Color(0xFF1DB954)),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      
                      // 2. Avatar
                      CircleAvatar(
                        radius: _isExpanded ? (isLive ? 26 : 28) : (isLive ? 32 : 35),
                        backgroundImage: widget.friend.photoUrl.isNotEmpty 
                            ? NetworkImage(widget.friend.photoUrl) 
                            : null,
                        backgroundColor: const Color(0xFF333333),
                        child: widget.friend.photoUrl.isEmpty 
                            ? Text(
                                widget.friend.username[0].toUpperCase(),
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: _isExpanded ? 16 : 20),
                              )
                            : null,
                      ),
                      
                      // 3. Dark overlay with centered equalizer (like mobile home)
                      if (isLive && !_isExpanded)
                        Container(
                          width: isLive ? 64 : 70,
                          height: isLive ? 64 : 70,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: _MiniEqualizer(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              
              // 2. The Music Info Panel (Only visible when expanded)
              if (_isExpanded)
                Positioned(
                  left: 85,
                  right: 10,
                  top: 10,
                  bottom: 10,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 80) return const SizedBox.shrink();
                      return ClipRect(
                        child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                           widget.friend.username,
                           style: const TextStyle(
                             color: Colors.white,
                             fontWeight: FontWeight.bold,
                             fontSize: 12,
                           ),
                           overflow: TextOverflow.ellipsis,
                        ),
                        if (isLive && widget.activity != null) ...[
                          Text(
                             widget.activity!.songTitle ?? 'Unknown Song',
                             style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                             overflow: TextOverflow.ellipsis,
                             maxLines: 1,
                          ),
                          Text(
                             widget.activity!.artistName ?? 'Unknown Artist',
                             style: const TextStyle(color: Colors.white54, fontSize: 9),
                             overflow: TextOverflow.ellipsis,
                             maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          ClipRect(
                            child: Row(
                              children: [
                                Text(widget.formattedTime, style: const TextStyle(color: Color(0xFF1DB954), fontSize: 9, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SizedBox(
                                    height: 2,
                                    child: LinearProgressIndicator(
                                      value: (widget.activity?.durationMs ?? 0) > 0 
                                          ? (widget.interpolatedPosition / (widget.activity?.durationMs ?? 1)).clamp(0.0, 1.0)
                                          : 0,
                                      backgroundColor: Colors.white10,
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF1DB954)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else
                          Text(
                            "Offline",
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Component: User Sun Node (Center)
// -----------------------------------------------------------------------------

class _UserSunNode extends StatelessWidget {
  const _UserSunNode();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
           width: 80,
           height: 80,
           decoration: BoxDecoration(
             shape: BoxShape.circle,
             gradient: const RadialGradient(
               colors: [Colors.white, Colors.blueAccent],
               center: Alignment(-0.3, -0.3),
             ),
             boxShadow: [
               BoxShadow(
                 color: Colors.blueAccent.withOpacity(0.5),
                 blurRadius: 30,
                 spreadRadius: 5,
               ),
             ],
           ),
           child: const Center(
             child: Icon(Icons.person, color: Colors.black, size: 30),
           ),
        ),
        const SizedBox(height: 8),
        const Text("YOU", style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
      ],
    );
  }
}

class _AnimatedStarPainter extends CustomPainter {
  final List<Offset> stars;
  final List<double> sizes;
  final List<double> baseOpacities;
  final List<double> twinkleSpeeds;
  final double animValue;

  _AnimatedStarPainter({
    required this.stars,
    required this.sizes,
    required this.baseOpacities,
    required this.twinkleSpeeds,
    required this.animValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    
    for (int i = 0; i < stars.length; i++) {
      // Calculate twinkling opacity using sin wave
      // Each star has its own speed and phase offset (based on index)
      final phase = (i * 0.1) % (2 * pi); // Stagger phases
      final twinkle = sin((animValue * twinkleSpeeds[i] * 2 * pi) + phase);
      
      // Map sin (-1 to 1) to opacity variation (0.3 to 1.0 of base)
      final opacityMultiplier = 0.5 + (twinkle + 1) * 0.25; // 0.5 to 1.0
      final finalOpacity = (baseOpacities[i] * opacityMultiplier).clamp(0.1, 1.0);
      
      paint.color = Colors.white.withOpacity(finalOpacity);
      
      // Slight size pulse for brighter stars
      final sizePulse = sizes[i] > 1.0 ? 1.0 + twinkle * 0.2 : 1.0;
      
      canvas.drawCircle(stars[i], sizes[i] * sizePulse, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedStarPainter oldDelegate) {
    return oldDelegate.animValue != animValue;
  }
}

// -----------------------------------------------------------------------------
// Component: Meteor Friend Request (Flying through space with fire tail!)
// -----------------------------------------------------------------------------

class _MeteorRequest extends StatefulWidget {
  final FriendRequest request;
  final int index;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _MeteorRequest({
    super.key,
    required this.request,
    required this.index,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_MeteorRequest> createState() => _MeteorRequestState();
}

class _MeteorRequestState extends State<_MeteorRequest> with TickerProviderStateMixin {
  late AnimationController _flyController;
  late AnimationController _glowController;
  late Animation<Offset> _positionAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Each meteor has a different flight path based on index
    final rng = Random(widget.request.id.hashCode);
    
    // Glow pulse animation
    _glowController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800 + rng.nextInt(400)),
    )..repeat(reverse: true);
    
    // Flight animation - meteors orbit around the center (slower for easier clicking)
    _flyController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 40 + rng.nextInt(20)), // 40-60 second orbit
    )..repeat();
    
    // Create an elliptical orbit path
    final orbitRadius = 800.0 + rng.nextDouble() * 600; // 800-1400 radius
    final startAngle = rng.nextDouble() * 2 * pi;
    
    _positionAnimation = TweenSequence<Offset>([
      for (int i = 0; i < 360; i += 10)
        TweenSequenceItem(
          tween: Tween(
            begin: Offset(
              2500 + orbitRadius * cos(startAngle + (i * pi / 180)),
              2500 + orbitRadius * sin(startAngle + (i * pi / 180)) * 0.6, // Elliptical
            ),
            end: Offset(
              2500 + orbitRadius * cos(startAngle + ((i + 10) * pi / 180)),
              2500 + orbitRadius * sin(startAngle + ((i + 10) * pi / 180)) * 0.6,
            ),
          ),
          weight: 1,
        ),
    ]).animate(_flyController);
  }

  @override
  void dispose() {
    _flyController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _showRequestDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _GlassThemeDialog(
        title: 'Incoming Meteor!',
        content: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.orange.withOpacity(0.5), blurRadius: 20),
                ],
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundImage: widget.request.fromUser.photoUrl.isNotEmpty
                    ? NetworkImage(widget.request.fromUser.photoUrl)
                    : null,
                backgroundColor: Colors.black,
                child: widget.request.fromUser.photoUrl.isEmpty
                    ? Text(widget.request.fromUser.username[0].toUpperCase(), style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold, fontSize: 16))
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.request.fromUser.username} wants to join yuw owbit!',
              textAlign: TextAlign.center,
              style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onReject();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: Text('Nu...', style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onAccept();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 8,
              shadowColor: Colors.white.withOpacity(0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('Yass!', style: GoogleFonts.mPlusRounded1c(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flyController, _glowController]),
      builder: (context, child) {
        final pos = _positionAnimation.value;
        
        // Calculate tail direction (opposite of movement)
        final angle = atan2(
          pos.dy - 2500,
          pos.dx - 2500,
        ) + pi; // Point away from center
        
        return Positioned(
          left: pos.dx - 30,
          top: pos.dy - 30,
          child: GestureDetector(
            onTap: _showRequestDialog,
            child: SizedBox(
              width: 120,
              height: 80,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Fire Trail (positioned behind meteor, rotated to follow motion)
                  Transform.rotate(
                    angle: angle + pi, // Point trail backwards
                    child: Transform.translate(
                      offset: const Offset(50, 0), // Radius (20) + HalfWidth (30) = 50
                      child: CustomPaint(
                        size: const Size(60, 24),
                        painter: _FireTrailPainter(
                          glowValue: _glowController.value,
                        ),
                      ),
                    ),
                  ),
                  
                  // Meteor Head (Avatar) - centered
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.orange.shade300,
                          Colors.deepOrange,
                          Colors.red.shade800,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.4 + _glowController.value * 0.3),
                          blurRadius: 12 + _glowController.value * 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: widget.request.fromUser.photoUrl.isNotEmpty
                          ? Image.network(
                              widget.request.fromUser.photoUrl,
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Text(
                                widget.request.fromUser.username[0].toUpperCase(),
                                style: GoogleFonts.mPlusRounded1c(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Fire trail painter for meteors
class _FireTrailPainter extends CustomPainter {
  final double glowValue;

  _FireTrailPainter({required this.glowValue});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    
    // Flame shape (elongated triangle with wavy edges)
    path.moveTo(0, size.height / 2);
    
    // Top edge with slight wave
    for (double x = 0; x < size.width; x += 10) {
      final wave = sin(x * 0.3 + glowValue * 2 * pi) * 3;
      final y = size.height / 2 - (size.height / 2) * (1 - x / size.width) + wave;
      path.lineTo(x, y);
    }
    
    path.lineTo(size.width, size.height / 2);
    
    // Bottom edge with slight wave
    for (double x = size.width; x > 0; x -= 10) {
      final wave = sin(x * 0.3 + glowValue * 2 * pi) * 3;
      final y = size.height / 2 + (size.height / 2) * (1 - x / size.width) + wave;
      path.lineTo(x, y);
    }
    
    path.close();

    // Gradient from orange to transparent
    final gradient = LinearGradient(
      colors: [
        Colors.orange.withOpacity(0.9),
        Colors.deepOrange.withOpacity(0.6),
        Colors.white.withOpacity(0.3),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.6, 1.0],
    );

    final paint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
    
    // Inner bright core
    final corePath = Path();
    corePath.moveTo(0, size.height / 2);
    corePath.lineTo(size.width * 0.4, size.height / 2 - 5);
    corePath.lineTo(size.width * 0.4, size.height / 2 + 5);
    corePath.close();
    
    final corePaint = Paint()
      ..color = Colors.yellow.withOpacity(0.8)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    
    canvas.drawPath(corePath, corePaint);
  }

  @override
  bool shouldRepaint(covariant _FireTrailPainter oldDelegate) {
    return oldDelegate.glowValue != glowValue;
  }
}
// -----------------------------------------------------------------------------
// Component: Glass Theme Dialog (Premium & UwU)
// -----------------------------------------------------------------------------

class _GlassThemeDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;

  const _GlassThemeDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(20),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.8, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: child,
          );
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withOpacity(0.95), // Deep smooth dark
            borderRadius: BorderRadius.circular(30), // Very rounded
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withOpacity(0.15),
                blurRadius: 50,
                spreadRadius: -10,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 360 ? 12 : 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Builder(
                builder: (context) {
                  final isSmall = MediaQuery.of(context).size.width < 360;
                  return Text(
                    title.toUpperCase(),
                    style: GoogleFonts.mPlusRounded1c(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: isSmall ? 11 : 13,
                      letterSpacing: isSmall ? 0.8 : 1.2,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
              ),
              const SizedBox(height: 6),
              Container(
                width: 30,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              DefaultTextStyle(
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: MediaQuery.of(context).size.width < 360 ? 12 : 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                child: content,
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Component: Mini Equalizer Animation
// -----------------------------------------------------------------------------

class _MiniEqualizer extends StatefulWidget {
  const _MiniEqualizer();

  @override
  State<_MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<_MiniEqualizer> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) => AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + i * 100),
    )..repeat(reverse: true));
    
    _animations = _controllers.map((c) => Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut))).toList();
  }

  @override
  void dispose() {
    for (var c in _controllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (_, __) => Container(
            width: 3,
            height: 14 * _animations[i].value,
            margin: EdgeInsets.only(left: i > 0 ? 2 : 0),
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }),
    );
  }
}
