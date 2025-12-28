import 'package:flutter/material.dart';

/// Skeleton shimmer effect for loading states
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool isCircle;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = 8,
    this.isCircle = false,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _animation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.isCircle ? widget.height : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.isCircle
                ? null
                : BorderRadius.circular(widget.borderRadius),
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            gradient: LinearGradient(
              begin: Alignment(_animation.value, 0),
              end: Alignment(_animation.value + 1, 0),
              colors: [
                Colors.grey[900]!,
                Colors.grey[800]!,
                Colors.grey[700]!,
                Colors.grey[800]!,
                Colors.grey[900]!,
              ],
              stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton for a song list item
class SkeletonSongItem extends StatelessWidget {
  final bool showNumber;
  final int? index;

  const SkeletonSongItem({super.key, this.showNumber = false, this.index});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showNumber) ...[
          SizedBox(
            width: 24,
            child: SkeletonLoader(width: 16, height: 14, borderRadius: 4),
          ),
          const SizedBox(width: 12),
        ],
        // Album art
        const SkeletonLoader(width: 48, height: 48, borderRadius: 6),
        const SizedBox(width: 12),
        // Title and artist
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonLoader(
                width: 100 + (index ?? 0) % 50.toDouble(),
                height: 14,
                borderRadius: 4,
              ),
              const SizedBox(height: 6),
              SkeletonLoader(
                width: 70 + (index ?? 0) % 30.toDouble(),
                height: 12,
                borderRadius: 4,
              ),
            ],
          ),
        ),
        // Duration
        const SkeletonLoader(width: 32, height: 12, borderRadius: 4),
      ],
    );
  }
}

/// Skeleton for a horizontal card (playlist, mix, etc.)
class SkeletonCard extends StatelessWidget {
  final double width;
  final double height;

  const SkeletonCard({super.key, this.width = 160, this.height = 160});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // Cover image skeleton (full size)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: const SkeletonLoader(borderRadius: 0),
            ),
          ),
          // Bottom gradient overlay with info
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SkeletonLoader(width: 80, height: 12, borderRadius: 4),
                  SizedBox(height: 4),
                  SkeletonLoader(width: 50, height: 10, borderRadius: 4),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for playlist grid card - fills parent container (for use in GridView)
class SkeletonPlaylistGridCard extends StatelessWidget {
  const SkeletonPlaylistGridCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover image skeleton
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const SkeletonLoader(borderRadius: 0),
            ),
          ),
          const SizedBox(height: 12),
          // Title
          const SkeletonLoader(width: 100, height: 14, borderRadius: 4),
          const SizedBox(height: 6),
          // Subtitle
          const SkeletonLoader(width: 60, height: 11, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Skeleton for a grid item (top of week, etc.)
class SkeletonGridItem extends StatelessWidget {
  const SkeletonGridItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SkeletonLoader(width: 44, height: 44, isCircle: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SkeletonLoader(width: 80, height: 13, borderRadius: 4),
              SizedBox(height: 6),
              SkeletonLoader(width: 50, height: 11, borderRadius: 4),
            ],
          ),
        ),
      ],
    );
  }
}

/// Skeleton for the hero/highlight section
class SkeletonHeroSection extends StatelessWidget {
  const SkeletonHeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          // Main large card
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181818),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const SkeletonLoader(borderRadius: 16),
            ),
          ),
          const SizedBox(width: 16),
          // Side cards
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const SkeletonLoader(borderRadius: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF181818),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const SkeletonLoader(borderRadius: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a section with title and horizontal list
class SkeletonSection extends StatelessWidget {
  final int itemCount;
  final double itemWidth;
  final double itemHeight;

  const SkeletonSection({
    super.key,
    this.itemCount = 4,
    this.itemWidth = 160,
    this.itemHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section title skeleton
        const SkeletonLoader(width: 120, height: 20, borderRadius: 4),
        const SizedBox(height: 16),
        // Horizontal list
        SizedBox(
          height: itemHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, __) =>
                SkeletonCard(width: itemWidth, height: itemHeight),
          ),
        ),
      ],
    );
  }
}

/// Skeleton for top of week grid
class SkeletonTopOfWeekGrid extends StatelessWidget {
  const SkeletonTopOfWeekGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Top of this week',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 3.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 16,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => const SkeletonGridItem(),
        ),
      ],
    );
  }
}

/// Skeleton for song list in a card
class SkeletonSongListCard extends StatelessWidget {
  final int itemCount;

  const SkeletonSongListCard({super.key, this.itemCount = 5});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Song list - limit to available space
          ...List.generate(
            itemCount,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index < itemCount - 1 ? 8 : 0),
              child: SkeletonSongItem(index: index),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for artist profile popular songs section
class SkeletonArtistSongs extends StatelessWidget {
  final int itemCount;
  final bool showNumbers;

  const SkeletonArtistSongs({
    super.key,
    this.itemCount = 5,
    this.showNumbers = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        itemCount,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (showNumbers) ...[
                SizedBox(
                  width: 24,
                  child: SkeletonLoader(width: 16, height: 14, borderRadius: 4),
                ),
                const SizedBox(width: 12),
              ],
              // Album art
              const SkeletonLoader(width: 48, height: 48, borderRadius: 6),
              const SizedBox(width: 12),
              // Title and stream count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      width: 120 + (index * 15) % 80,
                      height: 14,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    SkeletonLoader(
                      width: 60 + (index * 10) % 40,
                      height: 12,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
              // Duration
              const SkeletonLoader(width: 36, height: 12, borderRadius: 4),
              const SizedBox(width: 8),
              // More button
              const SkeletonLoader(width: 24, height: 24, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for artist profile albums section (mobile - vertical list)
class SkeletonArtistAlbumsList extends StatelessWidget {
  final int itemCount;

  const SkeletonArtistAlbumsList({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Album cover
              const SkeletonLoader(width: 64, height: 64, borderRadius: 4),
              const SizedBox(width: 12),
              // Album info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      width: 100 + (index * 20) % 60,
                      height: 14,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    const SkeletonLoader(
                      width: 80,
                      height: 12,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
              // More icon
              const SkeletonLoader(width: 24, height: 24, borderRadius: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for artist profile albums grid (desktop)
class SkeletonArtistAlbumsGrid extends StatelessWidget {
  final int itemCount;
  final int crossAxisCount;

  const SkeletonArtistAlbumsGrid({
    super.key,
    this.itemCount = 5,
    this.crossAxisCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.65,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album cover
          const AspectRatio(
            aspectRatio: 1,
            child: SkeletonLoader(borderRadius: 8),
          ),
          const SizedBox(height: 8),
          // Album name
          SkeletonLoader(
            width: 80 + (index * 15) % 40,
            height: 13,
            borderRadius: 4,
          ),
          const SizedBox(height: 4),
          // Year
          const SkeletonLoader(width: 50, height: 11, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Skeleton for mobile artist profile stats and buttons
class SkeletonArtistStats extends StatelessWidget {
  const SkeletonArtistStats({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Monthly listeners
          const SkeletonLoader(width: 120, height: 14, borderRadius: 4),
          const SizedBox(height: 16),
          // Action buttons row
          Row(
            children: [
              // Follow button
              const SkeletonLoader(width: 90, height: 32, borderRadius: 16),
              const SizedBox(width: 12),
              // More button
              const SkeletonLoader(width: 32, height: 32, borderRadius: 16),
              const Spacer(),
              // Shuffle button
              const SkeletonLoader(width: 32, height: 32, borderRadius: 16),
              const SizedBox(width: 12),
              // Play button
              const SkeletonLoader(width: 48, height: 48, isCircle: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for sidebar playlist/album/artist item
class SkeletonSidebarItem extends StatelessWidget {
  final bool isCircular;

  const SkeletonSidebarItem({super.key, this.isCircular = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Cover image
          SkeletonLoader(
            width: 48,
            height: 48,
            borderRadius: isCircular ? 24 : 6,
            isCircle: isCircular,
          ),
          const SizedBox(width: 12),
          // Title and subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonLoader(width: 100, height: 13, borderRadius: 4),
                SizedBox(height: 6),
                SkeletonLoader(width: 60, height: 11, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for sidebar section with multiple items
class SkeletonSidebarSection extends StatelessWidget {
  final int itemCount;
  final bool isCircular;

  const SkeletonSidebarSection({
    super.key,
    this.itemCount = 4,
    this.isCircular = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => SkeletonSidebarItem(isCircular: isCircular),
      ),
    );
  }
}

/// Skeleton for friends activity section
class SkeletonFriendsActivity extends StatelessWidget {
  final int itemCount;

  const SkeletonFriendsActivity({super.key, this.itemCount = 3});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        itemCount,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Circular avatar
              const SkeletonLoader(width: 34, height: 34, isCircle: true),
              const SizedBox(width: 12),
              // Name and song info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLoader(
                      width: 70 + (index * 15) % 30,
                      height: 12,
                      borderRadius: 4,
                    ),
                    const SizedBox(height: 6),
                    SkeletonLoader(
                      width: 90 + (index * 10) % 40,
                      height: 10,
                      borderRadius: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
