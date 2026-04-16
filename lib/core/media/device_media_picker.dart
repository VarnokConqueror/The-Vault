import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

enum DeviceMediaPickerMode { image, video, mixed }

class DeviceMediaSelection {
  final String path;
  final String name;
  final AssetType type;

  const DeviceMediaSelection({
    required this.path,
    required this.name,
    required this.type,
  });
}

Future<DeviceMediaSelection?> showDeviceMediaPicker(
  BuildContext context, {
  required String title,
  DeviceMediaPickerMode mode = DeviceMediaPickerMode.mixed,
}) {
  return Navigator.of(context).push<DeviceMediaSelection>(
    MaterialPageRoute<DeviceMediaSelection>(
      builder: (_) => DeviceMediaPickerScreen(title: title, mode: mode),
    ),
  );
}

class DeviceMediaPickerScreen extends StatefulWidget {
  final String title;
  final DeviceMediaPickerMode mode;

  const DeviceMediaPickerScreen({
    super.key,
    required this.title,
    required this.mode,
  });

  @override
  State<DeviceMediaPickerScreen> createState() => _DeviceMediaPickerScreenState();
}

class _DeviceMediaPickerScreenState extends State<DeviceMediaPickerScreen> {
  static const Color _pink = Color(0xFFFF2DAA);
  static const Color _screenBg = Color(0xFF140019);
  static const Color _panel = Color(0xFF1A0024);

  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  bool _loadingMore = false;
  bool _permissionDenied = false;
  String? _error;
  List<AssetPathEntity> _albums = const <AssetPathEntity>[];
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _assets = const <AssetEntity>[];
  int _page = 0;
  bool _hasMore = true;

  RequestType get _requestType {
    switch (widget.mode) {
      case DeviceMediaPickerMode.image:
        return RequestType.image;
      case DeviceMediaPickerMode.video:
        return RequestType.video;
      case DeviceMediaPickerMode.mixed:
        return RequestType.common;
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      unawaited(_loadMore());
    }
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
      _error = null;
    });

    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _permissionDenied = true;
          _albums = const <AssetPathEntity>[];
          _assets = const <AssetEntity>[];
        });
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: _requestType,
        filterOption: FilterOptionGroup(
          orders: const <OrderOption>[
            OrderOption(type: OrderOptionType.createDate, asc: false),
          ],
        ),
      );

      if (!mounted) return;
      setState(() {
        _albums = albums;
        _selectedAlbum = albums.isEmpty ? null : albums.first;
        _assets = const <AssetEntity>[];
        _page = 0;
        _hasMore = true;
        _loading = false;
      });

      if (_selectedAlbum != null) {
        await _loadMore(reset: true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not open your albums.';
      });
      debugPrint('[MediaPicker] bootstrap failed: $error');
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    final album = _selectedAlbum;
    if (album == null || _loadingMore) return;

    setState(() {
      _loadingMore = true;
      if (reset) {
        _page = 0;
        _hasMore = true;
        _assets = const <AssetEntity>[];
      }
    });

    try {
      final nextPage = _page;
      final pageItems = await album.getAssetListPaged(page: nextPage, size: 80);
      if (!mounted) return;
      setState(() {
        _assets = reset ? pageItems : <AssetEntity>[..._assets, ...pageItems];
        _page = nextPage + 1;
        _hasMore = pageItems.length == 80;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = 'Could not load this album.';
      });
      debugPrint('[MediaPicker] loadMore failed: $error');
    }
  }

  Future<void> _selectAlbum(AssetPathEntity? album) async {
    if (album == null) return;
    setState(() {
      _selectedAlbum = album;
      _error = null;
    });
    await _loadMore(reset: true);
  }

  Future<void> _pickAsset(AssetEntity asset) async {
    try {
      final file = await _materializeAssetFile(asset);
      final path = file?.path;
      if (path == null || path.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That item could not be opened.')),
        );
        return;
      }
      final title = (await asset.titleAsync).trim();
      final fallbackName = path.split(RegExp(r'[\\\/]+')).last.trim();
      if (!mounted) return;
      Navigator.of(context).pop(
        DeviceMediaSelection(
          path: path.trim(),
          name: title.isEmpty ? fallbackName : title,
          type: asset.type,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That item could not be opened.')),
      );
      debugPrint('[MediaPicker] pick failed: $error');
    }
  }

  Future<File?> _materializeAssetFile(AssetEntity asset) async {
    final directFile = await asset.originFile ?? await asset.file;
    if (directFile != null) {
      try {
        if (await directFile.exists()) {
          return _copyAssetFileToTemp(asset, directFile);
        }
      } catch (_) {
        // Fall through to byte extraction below.
      }
    }

    final bytes = await asset.originBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final tempRoot = await getTemporaryDirectory();
    final tempDir = Directory('${tempRoot.path}${Platform.pathSeparator}vault_picker');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    final fileName = await _assetFileName(asset, fallbackPath: directFile?.path);
    final output = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await output.writeAsBytes(bytes, flush: true);
    return output;
  }

  Future<File> _copyAssetFileToTemp(AssetEntity asset, File source) async {
    final tempRoot = await getTemporaryDirectory();
    final tempDir = Directory('${tempRoot.path}${Platform.pathSeparator}vault_picker');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    final fileName = await _assetFileName(asset, fallbackPath: source.path);
    final output = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await source.copy(output.path);
    return output;
  }

  Future<String> _assetFileName(
    AssetEntity asset, {
    String? fallbackPath,
  }) async {
    final rawTitle = (await asset.titleAsync).trim();
    final fallbackName = (fallbackPath ?? '').split(RegExp(r'[\\\/]+')).last.trim();
    final baseName = rawTitle.isNotEmpty ? rawTitle : fallbackName;
    final cleaned = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final hasExtension = cleaned.contains('.') && !cleaned.endsWith('.');
    final extension = hasExtension
        ? ''
        : asset.type == AssetType.video
        ? '.mp4'
        : '.jpg';
    return '${asset.id}_${DateTime.now().millisecondsSinceEpoch}_$cleaned$extension';
  }

  String _albumTypeLabel() {
    switch (widget.mode) {
      case DeviceMediaPickerMode.image:
        return 'albums';
      case DeviceMediaPickerMode.video:
        return 'video albums';
      case DeviceMediaPickerMode.mixed:
        return 'albums';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: AppBar(
        backgroundColor: _screenBg,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.photo_library_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pick straight from device albums. No cloud file picker mess.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_albums.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AssetPathEntity>(
                      isExpanded: true,
                      dropdownColor: _panel,
                      value: _selectedAlbum,
                      iconEnabledColor: Colors.white70,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      hint: const Text(
                        'Choose album',
                        style: TextStyle(color: Colors.white70),
                      ),
                      items: _albums
                          .map(
                            (album) => DropdownMenuItem<AssetPathEntity>(
                              value: album,
                              child: Text(
                                album.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _selectAlbum,
                    ),
                  ),
                ),
              ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.photo_library_outlined,
                color: Colors.white70,
                size: 42,
              ),
              const SizedBox(height: 14),
              Text(
                'Vault needs photo access to open your ${_albumTypeLabel()}.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enable photo access in system settings, then come right back here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                ),
                onPressed: PhotoManager.openSetting,
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }
    if ((_error ?? '').isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _bootstrap,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }
    if (_albums.isEmpty || _selectedAlbum == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            'No matching media showed up in your local albums yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ),
      );
    }
    if (_assets.isEmpty && !_loadingMore) {
      return Center(
        child: Text(
          'This album is empty.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white70,
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width >= 900
        ? 5
        : width >= 680
        ? 4
        : 3;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _assets.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _assets.length) {
          return Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return _DeviceMediaGridTile(
          asset: _assets[index],
          onTap: () => _pickAsset(_assets[index]),
        );
      },
    );
  }
}

class _DeviceMediaGridTile extends StatelessWidget {
  final AssetEntity asset;
  final VoidCallback onTap;

  const _DeviceMediaGridTile({required this.asset, required this.onTap});

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final secs = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1A0024),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                FutureBuilder<Uint8List?>(
                  future: asset.thumbnailDataWithSize(
                    const ThumbnailSize(420, 420),
                  ),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null) {
                      return Container(
                        color: Colors.black.withValues(alpha: 0.16),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    return Image.memory(
                      data,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    );
                  },
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Row(
                    children: [
                      if (asset.type == AssetType.video)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(asset.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Photo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.58),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
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
