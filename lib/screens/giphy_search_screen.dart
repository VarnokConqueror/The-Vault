import 'package:flutter/material.dart';

import '../core/gifs/giphy_service.dart';
import '../core/ui/desktop_overlay_card.dart';

class GiphySearchScreen extends StatefulWidget {
  const GiphySearchScreen({super.key});

  @override
  State<GiphySearchScreen> createState() => _GiphySearchScreenState();
}

class _GiphySearchScreenState extends State<GiphySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<GiphyGif> _items = <GiphyGif>[];

  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _nextOffset = 0;
  String _query = '';
  String? _errorMessage;
  String? _downloadingGifId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_loadingMore || !_hasMore) return;
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 500;
    if (_scrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _items.clear();
      _hasMore = false;
      _nextOffset = 0;
    });
    final result = await GiphyService.search(_query, offset: 0);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items.addAll(result.items);
      _hasMore = result.hasMore;
      _nextOffset = result.nextOffset;
      _errorMessage = result.errorMessage;
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final result = await GiphyService.search(_query, offset: _nextOffset);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      _items.addAll(result.items);
      _hasMore = result.hasMore;
      _nextOffset = result.nextOffset;
      _errorMessage = result.errorMessage;
    });
  }

  Future<void> _selectGif(GiphyGif gif) async {
    if (_downloadingGifId != null) return;
    setState(() {
      _downloadingGifId = gif.id;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Downloading GIF...')));
    final path = await GiphyService.downloadGif(gif);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    setState(() {
      _downloadingGifId = null;
    });
    if (path == null || path.trim().isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not download this GIF.')),
      );
      return;
    }
    Navigator.pop(context, path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desktopCard = useDesktopOverlayCards(context);
    final maxContentWidth = desktopCard ? 680.0 : double.infinity;
    return Scaffold(
      backgroundColor: desktopCard
          ? Colors.transparent
          : const Color(0xFF120918),
      appBar: AppBar(
        title: const Text('GIPHY'),
        backgroundColor: const Color(0xFF171121),
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(desktopCard ? 14 : 16, 14, 16, 12),
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    _query = value.trim();
                    _loadInitial();
                  },
                  style: const TextStyle(color: Colors.white),
                  cursorColor: const Color(0xFFF3A0FF),
                  decoration: InputDecoration(
                    hintText: 'Search GIFs',
                    hintStyle: const TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      tooltip: 'Search',
                      onPressed: () {
                        _query = _searchController.text.trim();
                        _loadInitial();
                      },
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: Color(0xFFF3A0FF),
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _query.isEmpty
                            ? 'Trending GIFs'
                            : 'Results for "$_query"',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Text(
                      'Powered by GIPHY',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null && _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ),
                      )
                    : _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'No GIFs matched this search yet.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.35,
                            ),
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadInitial,
                        child: GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: desktopCard ? 3 : 2,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: desktopCard ? 0.94 : 1,
                              ),
                          itemCount: _items.length + (_loadingMore ? 2 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _items.length) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            final gif = _items[index];
                            return _GifTile(
                              gif: gif,
                              busy: _downloadingGifId == gif.id,
                              onTap: () => _selectGif(gif),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GifTile extends StatelessWidget {
  const _GifTile({required this.gif, required this.onTap, this.busy = false});

  final GiphyGif gif;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  gif.previewUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.hide_image_outlined,
                      color: Colors.white54,
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : const Text(
                            'Send GIF',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
