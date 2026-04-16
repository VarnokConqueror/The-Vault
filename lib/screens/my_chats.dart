import 'package:flutter/material.dart';

import '../core/ui/desktop_overlay_card.dart';
import '../core/ui/vault_avatar.dart';
import '../models/chat_thread.dart';
import '../state/chat_category_store.dart';
import '../state/chat_store.dart';
import '../state/chat_unread_store.dart';
import '../state/date_time_format_store.dart';
import '../state/identity_store.dart';
import '../state/message_store.dart';
import '../state/vault_theme_store.dart';
import 'contacts_screen.dart';
import 'profile_screen.dart';
import 'join_chat.dart';
import 'start_chat.dart';
import 'thread_screen.dart';
import 'vault_drawer.dart';

Color get _vaultBgA => VaultThemeStore.activePalette.backgroundAlt;
Color get _vaultBgB => VaultThemeStore.activePalette.background;
Color get _vaultPanel => VaultThemeStore.activePalette.surface;
Color get _vaultPanelAlt => VaultThemeStore.activePalette.surfaceAlt;
Color get _vaultPanelHover =>
    Color.lerp(_vaultPanelAlt, _vaultBgA, 0.35) ?? _vaultPanelAlt;
Color get _vaultPink => VaultThemeStore.activePalette.accent;
Color get _vaultPurple => VaultThemeStore.activePalette.accent2;
Color get _vaultBlue => VaultThemeStore.activePalette.header;
Color get _vaultText => VaultThemeStore.activePalette.text;
Color get _vaultTextSoft => VaultThemeStore.activePalette.textSoft;

class MyChatsScreen extends StatefulWidget {
  const MyChatsScreen({super.key, this.overlayMode = false});

  final bool overlayMode;

  @override
  State<MyChatsScreen> createState() => _MyChatsScreenState();
}

class _MyChatsScreenState extends State<MyChatsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedChatId;
  String _searchQuery = '';
  String _selectedCategory = ChatThread.allCategory;
  bool _showCategoryFilters = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim();
    if (next == _searchQuery) return;
    setState(() {
      _searchQuery = next;
    });
  }

  void _openContacts() {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/contacts'),
      maxWidth: 720,
      builder: (_) => const ContactsScreen(),
    );
  }

  void _openProfile() {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/profile'),
      maxWidth: 560,
      builder: (_) => const ProfileScreen(),
    );
  }

  void _openThread(ChatThread chat, {required bool embedded}) {
    final title = _displayTitle(chat);
    if (embedded) {
      setState(() {
        _selectedChatId = chat.id;
      });
      return;
    }
    if (useDesktopOverlayCards(context)) {
      pushOrPresentDesktopCard<void>(
        context,
        settings: RouteSettings(name: '/thread/${chat.id}'),
        maxWidth: 920,
        builder: (_) => ThreadScreen(
          chatId: chat.id,
          chatTitle: title,
          contactId: chat.contactId,
          embedded: false,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ThreadScreen(
          chatId: chat.id,
          chatTitle: title,
          contactId: chat.contactId,
        ),
      ),
    );
  }

  void _openStartChat() {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/start'),
      maxWidth: 700,
      builder: (_) => const StartChatScreen(),
    );
  }

  void _openJoinChat() {
    pushOrPresentDesktopCard<void>(
      context,
      settings: const RouteSettings(name: '/join'),
      maxWidth: 760,
      builder: (_) => const JoinChatScreen(),
    );
  }

  String _displayTitle(ChatThread chat) {
    final trimmed = chat.title.trim();
    if (trimmed.isNotEmpty) return trimmed;
    return chat.isDirectThread ? 'Chat' : 'Group';
  }

  String _previewForChat(ChatThread chat) {
    final messages = MessageStore.getMessagesForChat(chat.id);
    if (messages.isEmpty) {
      return chat.isDirectThread ? 'Conversation' : 'Group conversation';
    }
    final last = messages.last;
    var prefix = '';
    if ((last.senderId).trim() == IdentityStore.userId.trim()) {
      prefix = 'You: ';
    }
    if (last.isVoiceNote) return '${prefix}Voice note';
    if (last.isSticker) return '${prefix}Sticker';
    if (last.isAttachment) {
      final mime = (last.attachmentMime ?? '').trim().toLowerCase();
      final label = mime.startsWith('image/')
          ? 'Photo'
          : mime.startsWith('video/')
          ? 'Video'
          : (last.attachmentName ?? 'Attachment').trim();
      return '$prefix$label';
    }
    final body = last.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return body.isEmpty ? '${prefix}New message' : '$prefix$body';
  }

  DateTime _latestActivityForChat(ChatThread chat) {
    final messages = MessageStore.getMessagesForChat(chat.id);
    if (messages.isEmpty) return chat.createdAt;
    return messages.last.createdAt;
  }

  bool _matchesQuery(ChatThread chat) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    final title = _displayTitle(chat).toLowerCase();
    final preview = _previewForChat(chat).toLowerCase();
    return title.contains(query) || preview.contains(query);
  }

  bool _matchesCategory(ChatThread chat, String selectedCategory) {
    if (selectedCategory == ChatThread.allCategory) return true;
    return chat.category == selectedCategory;
  }

  bool _shouldShowCategoryFilters(
    List<String> categories,
    String selectedCategory,
  ) {
    if (categories.length <= 1) return false;
    return _showCategoryFilters || selectedCategory != ChatThread.allCategory;
  }

  ChatThread? _resolveSelectedChat(List<ChatThread> chats) {
    if (chats.isEmpty) return null;
    final selectedId = (_selectedChatId ?? '').trim();
    if (selectedId.isNotEmpty) {
      for (final chat in chats) {
        if (chat.id == selectedId) {
          return chat;
        }
      }
    }
    return chats.first;
  }

  String _formatTimestamp(BuildContext context, DateTime dateTime) {
    return DateTimeFormatStore.formatListTimestamp(context, dateTime);
  }

  Widget _buildModernMobileBody({
    required BuildContext context,
    required List<String> categories,
    required String selectedCategory,
    required bool showCategoryFilters,
    required List<ChatThread> chats,
    required List<ChatThread> filteredChats,
    required bool showSearchEmpty,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Chats',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: _vaultText,
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Chats and groups, in one tighter view.',
                style: TextStyle(color: _vaultTextSoft, fontSize: 10.6),
              ),
              const SizedBox(height: 4),
              _SearchField(
                controller: _searchController,
                hintText: 'Search chats',
              ),
              if (categories.length > 1) ...[
                const SizedBox(height: 4),
                _CategoryFilterToggle(
                  showFilters: showCategoryFilters,
                  selectedCategory: selectedCategory,
                  onTap: () {
                    setState(() {
                      final next = !_showCategoryFilters;
                      _showCategoryFilters = next;
                      if (!next) {
                        _selectedCategory = ChatThread.allCategory;
                      }
                    });
                  },
                ),
                if (showCategoryFilters) ...[
                  const SizedBox(height: 4),
                  _CategoryFilterBar(
                    categories: categories,
                    selectedCategory: selectedCategory,
                    onCategoryChanged: (value) {
                      setState(() {
                        _selectedCategory = value;
                        if (value != ChatThread.allCategory) {
                          _showCategoryFilters = true;
                        }
                      });
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
        Expanded(
          child: showSearchEmpty
              ? _NoSearchResults(
                  onClear: () {
                    _searchController.clear();
                  },
                )
              : filteredChats.isEmpty
              ? _MobileEmptyState(
                  onNewChat: _openStartChat,
                  onJoinChat: _openJoinChat,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  itemCount: filteredChats.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 1),
                  itemBuilder: (context, index) {
                    final chat = filteredChats[index];
                    return _ModernChatCard(
                      chat: chat,
                      title: _displayTitle(chat),
                      preview: _previewForChat(chat),
                      timestamp: _formatTimestamp(
                        context,
                        _latestActivityForChat(chat),
                      ),
                      unreadCount: ChatUnreadStore.unreadForChat(chat.id),
                      onTap: () => _openThread(chat, embedded: false),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!IdentityStore.usernameCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      });
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: Listenable.merge([
        ChatStore.chatsNotifier,
        ChatCategoryStore.categoriesNotifier,
        ChatUnreadStore.unreadNotifier,
        DateTimeFormatStore.formatNotifier,
        MessageStore.messagesNotifier,
        IdentityStore.identityNotifier,
        VaultThemeStore.themeNotifier,
      ]),
      builder: (context, _) {
        final chats = ChatStore.chatsNotifier.value;
        final categoryOptions = ChatCategoryStore.categoriesForChats(chats);
        final totalUnread = ChatUnreadStore.totalUnread;
        final selectedCategory = categoryOptions.contains(_selectedCategory)
            ? _selectedCategory
            : ChatThread.allCategory;
        final showCategoryFilters = _shouldShowCategoryFilters(
          categoryOptions,
          selectedCategory,
        );
        final filteredChats = chats
            .where((chat) => _matchesCategory(chat, selectedCategory))
            .where(_matchesQuery)
            .toList(growable: false);

        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= kDesktopWideShellBreakpoint;
            final useDesktopShell = isWide && !widget.overlayMode;
            final showSearchEmpty = chats.isNotEmpty && filteredChats.isEmpty;
            final selectedChat = showSearchEmpty
                ? null
                : _resolveSelectedChat(
                    filteredChats.isNotEmpty ? filteredChats : chats,
                  );

            return Scaffold(
              backgroundColor: _vaultBgB,
              drawer: widget.overlayMode ? null : const VaultDrawer(),
              appBar: useDesktopShell
                  ? null
                  : AppBar(
                      backgroundColor: _vaultPanel,
                      surfaceTintColor: Colors.transparent,
                      leading: widget.overlayMode
                          ? null
                          : Builder(
                              builder: (context) => IconButton(
                                tooltip: 'Menu',
                                onPressed: () =>
                                    Scaffold.of(context).openDrawer(),
                                icon: const Icon(Icons.menu_rounded),
                              ),
                            ),
                      automaticallyImplyLeading: !widget.overlayMode,
                      title: Text(widget.overlayMode ? 'Chats' : 'The Vault'),
                    ),
              body: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_vaultBgA, _vaultBgB],
                  ),
                ),
                child: SafeArea(
                  child: useDesktopShell
                      ? Builder(
                          builder: (scaffoldContext) => Padding(
                            padding: const EdgeInsets.all(10),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1260,
                                ),
                                child: Row(
                                  children: [
                                    _DesktopRail(
                                      username: IdentityStore.displayName,
                                      totalUnread: totalUnread,
                                      onMenu: () => Scaffold.of(
                                        scaffoldContext,
                                      ).openDrawer(),
                                      onContacts: _openContacts,
                                      onNewChat: _openStartChat,
                                      onJoinChat: _openJoinChat,
                                      onProfile: _openProfile,
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: (constraints.maxWidth * 0.28)
                                          .clamp(256.0, 320.0),
                                      child: _DesktopChatListPane(
                                        searchController: _searchController,
                                        chats: filteredChats,
                                        categories: categoryOptions,
                                        selectedCategory: selectedCategory,
                                        showCategoryFilters:
                                            showCategoryFilters,
                                        onCategoryChanged: (value) {
                                          setState(() {
                                            _selectedCategory = value;
                                            if (value !=
                                                ChatThread.allCategory) {
                                              _showCategoryFilters = true;
                                            }
                                          });
                                        },
                                        onToggleCategoryFilters: () {
                                          setState(() {
                                            final next = !_showCategoryFilters;
                                            _showCategoryFilters = next;
                                            if (!next) {
                                              _selectedCategory =
                                                  ChatThread.allCategory;
                                            }
                                          });
                                        },
                                        hasChats: chats.isNotEmpty,
                                        showSearchEmpty: showSearchEmpty,
                                        selectedChatId: selectedChat?.id,
                                        displayTitle: _displayTitle,
                                        previewForChat: _previewForChat,
                                        latestActivityForChat:
                                            _latestActivityForChat,
                                        formatTimestamp: (dt) =>
                                            _formatTimestamp(context, dt),
                                        unreadForChat:
                                            ChatUnreadStore.unreadForChat,
                                        onSelect: (chat) =>
                                            _openThread(chat, embedded: true),
                                        onNewChat: _openStartChat,
                                        onJoinChat: _openJoinChat,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _DesktopConversationPane(
                                        chat: selectedChat,
                                        hasChats: chats.isNotEmpty,
                                        onStartChat: _openStartChat,
                                        onJoinChat: _openJoinChat,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : widget.overlayMode && useDesktopOverlayCards(context)
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: _DesktopChatListPane(
                                searchController: _searchController,
                                chats: filteredChats,
                                categories: categoryOptions,
                                selectedCategory: selectedCategory,
                                showCategoryFilters: showCategoryFilters,
                                onCategoryChanged: (value) {
                                  setState(() {
                                    _selectedCategory = value;
                                    if (value != ChatThread.allCategory) {
                                      _showCategoryFilters = true;
                                    }
                                  });
                                },
                                onToggleCategoryFilters: () {
                                  setState(() {
                                    final next = !_showCategoryFilters;
                                    _showCategoryFilters = next;
                                    if (!next) {
                                      _selectedCategory =
                                          ChatThread.allCategory;
                                    }
                                  });
                                },
                                hasChats: chats.isNotEmpty,
                                showSearchEmpty: showSearchEmpty,
                                selectedChatId: null,
                                displayTitle: _displayTitle,
                                previewForChat: _previewForChat,
                                latestActivityForChat: _latestActivityForChat,
                                formatTimestamp: (dt) =>
                                    _formatTimestamp(context, dt),
                                unreadForChat: ChatUnreadStore.unreadForChat,
                                onSelect: (chat) =>
                                    _openThread(chat, embedded: false),
                                onNewChat: _openStartChat,
                                onJoinChat: _openJoinChat,
                                compactHeader: true,
                              ),
                            ),
                          ),
                        )
                      : _buildModernMobileBody(
                          context: context,
                          categories: categoryOptions,
                          selectedCategory: selectedCategory,
                          showCategoryFilters: showCategoryFilters,
                          chats: chats,
                          filteredChats: filteredChats,
                          showSearchEmpty: showSearchEmpty,
                        ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.username,
    required this.totalUnread,
    required this.onMenu,
    required this.onContacts,
    required this.onNewChat,
    required this.onJoinChat,
    required this.onProfile,
  });

  final String username;
  final int totalUnread;
  final VoidCallback onMenu;
  final VoidCallback onContacts;
  final VoidCallback onNewChat;
  final VoidCallback onJoinChat;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    final trimmed = username.trim();
    final initial = trimmed.isEmpty
        ? 'V'
        : trimmed.characters.first.toUpperCase();
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: _vaultPanel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          IconButton(
            tooltip: 'Menu',
            onPressed: onMenu,
            icon: Icon(Icons.menu_rounded, color: _vaultText, size: 20),
          ),
          const SizedBox(height: 10),
          VaultAvatar(
            imagePath: IdentityStore.identity.avatarPath,
            initials: initial,
            radius: 21,
            borderWidth: 1,
            textStyle: TextStyle(
              color: _vaultText,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              username,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _vaultText,
                fontWeight: FontWeight.w700,
                fontSize: 11.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _RailButton(
            label: 'Chats',
            icon: Icons.chat_bubble_rounded,
            selected: true,
            badgeCount: totalUnread,
          ),
          _RailButton(
            label: 'Profile',
            icon: Icons.person_rounded,
            onTap: onProfile,
          ),
          _RailButton(
            label: 'Contacts',
            icon: Icons.people_alt_rounded,
            onTap: onContacts,
          ),
          _RailButton(
            label: 'New',
            icon: Icons.add_comment_rounded,
            onTap: onNewChat,
          ),
          _RailButton(
            label: 'Join',
            icon: Icons.group_add_rounded,
            onTap: onJoinChat,
          ),
          const Spacer(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DesktopChatListPane extends StatelessWidget {
  const _DesktopChatListPane({
    required this.searchController,
    required this.chats,
    required this.categories,
    required this.selectedCategory,
    required this.showCategoryFilters,
    required this.onCategoryChanged,
    required this.onToggleCategoryFilters,
    required this.hasChats,
    required this.showSearchEmpty,
    required this.selectedChatId,
    required this.displayTitle,
    required this.previewForChat,
    required this.latestActivityForChat,
    required this.formatTimestamp,
    required this.unreadForChat,
    required this.onSelect,
    required this.onNewChat,
    required this.onJoinChat,
    this.compactHeader = false,
  });

  final TextEditingController searchController;
  final List<ChatThread> chats;
  final List<String> categories;
  final String selectedCategory;
  final bool showCategoryFilters;
  final ValueChanged<String> onCategoryChanged;
  final VoidCallback onToggleCategoryFilters;
  final bool hasChats;
  final bool showSearchEmpty;
  final String? selectedChatId;
  final String Function(ChatThread chat) displayTitle;
  final String Function(ChatThread chat) previewForChat;
  final DateTime Function(ChatThread chat) latestActivityForChat;
  final String Function(DateTime dateTime) formatTimestamp;
  final int Function(String chatId) unreadForChat;
  final ValueChanged<ChatThread> onSelect;
  final VoidCallback onNewChat;
  final VoidCallback onJoinChat;
  final bool compactHeader;

  @override
  Widget build(BuildContext context) {
    final hasOptionalCategories = categories.length > 1;
    return Container(
      decoration: BoxDecoration(
        color: _vaultPanelAlt,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compactHeader ? 8 : 10,
              compactHeader ? 7 : 9,
              compactHeader ? 8 : 10,
              compactHeader ? 3 : 5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compactHeader)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Chats',
                          style: TextStyle(
                            color: _vaultText,
                            fontSize: 12.8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'New Group',
                        onPressed: onNewChat,
                        icon: const Icon(Icons.add_comment_rounded),
                        color: _vaultTextSoft,
                        iconSize: 16,
                        splashRadius: 14,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -2,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Join Group',
                        onPressed: onJoinChat,
                        icon: const Icon(Icons.group_add_rounded),
                        color: _vaultTextSoft,
                        iconSize: 16,
                        splashRadius: 14,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -2,
                          vertical: -2,
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    'Chats',
                    style: TextStyle(
                      color: _vaultText,
                      fontSize: 15.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Secure conversations, all in one place.',
                    style: TextStyle(color: _vaultTextSoft, fontSize: 10.1),
                  ),
                ],
                SizedBox(height: compactHeader ? 3 : 6),
                _SearchField(
                  controller: searchController,
                  hintText: 'Search chats',
                ),
                if (hasOptionalCategories) ...[
                  SizedBox(height: compactHeader ? 3 : 5),
                  _CategoryFilterToggle(
                    showFilters: showCategoryFilters,
                    selectedCategory: selectedCategory,
                    onTap: onToggleCategoryFilters,
                  ),
                  if (showCategoryFilters) ...[
                    SizedBox(height: compactHeader ? 2 : 4),
                    _CategoryFilterBar(
                      categories: categories,
                      selectedCategory: selectedCategory,
                      onCategoryChanged: onCategoryChanged,
                    ),
                  ],
                  SizedBox(height: compactHeader ? 1 : 4),
                ] else
                  SizedBox(height: compactHeader ? 1 : 4),
                if (!compactHeader)
                  Row(
                    children: [
                      Expanded(
                        child: _PrimaryGradientButton(
                          text: 'New Group',
                          icon: Icons.add_comment_rounded,
                          onTap: onNewChat,
                          bgA: _vaultPanel,
                          bgB: _vaultPanelAlt,
                          neonPink: _vaultPink,
                          neonPurple: _vaultPurple,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _SecondaryButton(
                          text: 'Join Group',
                          icon: Icons.group_add_rounded,
                          onTap: onJoinChat,
                          bg: _vaultPanel,
                          outline: _vaultPurple.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            child: !hasChats
                ? _DesktopEmptyListState(
                    onNewChat: onNewChat,
                    onJoinChat: onJoinChat,
                  )
                : showSearchEmpty
                ? _NoSearchResults(onClear: () => searchController.clear())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 1),
                    itemBuilder: (context, index) {
                      final chat = chats[index];
                      return _ChatListRow(
                        chat: chat,
                        title: displayTitle(chat),
                        preview: previewForChat(chat),
                        timestamp: formatTimestamp(latestActivityForChat(chat)),
                        unreadCount: unreadForChat(chat.id),
                        selected: chat.id == selectedChatId,
                        onTap: () => onSelect(chat),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DesktopConversationPane extends StatelessWidget {
  const _DesktopConversationPane({
    required this.chat,
    required this.hasChats,
    required this.onStartChat,
    required this.onJoinChat,
  });

  final ChatThread? chat;
  final bool hasChats;
  final VoidCallback onStartChat;
  final VoidCallback onJoinChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _vaultPanel,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: chat == null
          ? _ConversationPlaceholder(
              hasChats: hasChats,
              onStartChat: onStartChat,
              onJoinChat: onJoinChat,
            )
          : ThreadScreen(
              key: ValueKey<String>(chat!.id),
              chatId: chat!.id,
              chatTitle: chat!.title.trim().isEmpty
                  ? (chat!.isDirectThread ? 'Chat' : 'Group')
                  : chat!.title,
              contactId: chat!.contactId,
              embedded: true,
            ),
    );
  }
}

class _ChatListRow extends StatelessWidget {
  const _ChatListRow({
    required this.chat,
    required this.title,
    required this.preview,
    required this.timestamp,
    required this.unreadCount,
    required this.selected,
    required this.onTap,
  });

  final ChatThread chat;
  final String title;
  final String preview;
  final String timestamp;
  final int unreadCount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = chat.isDirectThread ? _vaultBlue : _vaultPurple;
    final trimmed = title.trim();
    final initial = trimmed.isEmpty
        ? 'V'
        : trimmed.characters.first.toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: selected
                ? _vaultPanelHover
                : Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? _vaultPink.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accent.withValues(alpha: 0.95),
                      _vaultPink.withValues(alpha: 0.88),
                    ],
                  ),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      color: _vaultText,
                      fontWeight: FontWeight.w800,
                      fontSize: 11.3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _vaultText,
                              fontSize: 11.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          timestamp,
                          style: TextStyle(
                            color: _vaultTextSoft,
                            fontSize: 8.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 4),
                          _UnreadBadge(count: unreadCount),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _vaultTextSoft,
                              height: 1.12,
                              fontSize: 9.5,
                            ),
                          ),
                        ),
                      ],
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

class _ModernChatCard extends StatelessWidget {
  const _ModernChatCard({
    required this.chat,
    required this.title,
    required this.preview,
    required this.timestamp,
    required this.unreadCount,
    required this.onTap,
  });

  final ChatThread chat;
  final String title;
  final String preview;
  final String timestamp;
  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = chat.isDirectThread ? _vaultBlue : _vaultPurple;
    final trimmed = title.trim();
    final initial = trimmed.isEmpty
        ? 'V'
        : trimmed.characters.first.toUpperCase();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.06),
              Colors.white.withValues(alpha: 0.02),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, _vaultPink.withValues(alpha: 0.94)],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  color: _vaultText,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.3,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _vaultText,
                            fontSize: 11.2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        timestamp,
                        style: TextStyle(
                          color: _vaultTextSoft,
                          fontSize: 8.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 4),
                        _UnreadBadge(count: unreadCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _vaultTextSoft,
                            height: 1.12,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: _vaultPink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: _vaultPink.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color:
              ThemeData.estimateBrightnessForColor(_vaultPink) ==
                  Brightness.dark
              ? Colors.white
              : const Color(0xFF14091D),
          fontSize: 10.4,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConversationPlaceholder extends StatelessWidget {
  const _ConversationPlaceholder({
    required this.hasChats,
    required this.onStartChat,
    required this.onJoinChat,
  });

  final bool hasChats;
  final VoidCallback onStartChat;
  final VoidCallback onJoinChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 94,
                height: 94,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _vaultPurple.withValues(alpha: 0.92),
                      _vaultPink.withValues(alpha: 0.92),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                hasChats ? 'Select a chat to begin' : 'No chats yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _vaultText,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                hasChats
                    ? 'Your active conversation stays open here while your chat list and tools stay within reach.'
                    : 'Create a new Vault conversation or join one with an invite, and it will appear here immediately.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _vaultTextSoft,
                  fontSize: 14.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _PrimaryGradientButton(
                      text: 'New Group',
                      icon: Icons.add_comment_rounded,
                      onTap: onStartChat,
                      bgA: _vaultPanel,
                      bgB: _vaultPanelAlt,
                      neonPink: _vaultPink,
                      neonPurple: _vaultPurple,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SecondaryButton(
                      text: 'Join Group',
                      icon: Icons.group_add_rounded,
                      onTap: onJoinChat,
                      bg: _vaultPanelAlt,
                      outline: _vaultPurple.withValues(alpha: 0.6),
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
}

class _DesktopEmptyListState extends StatelessWidget {
  const _DesktopEmptyListState({
    required this.onNewChat,
    required this.onJoinChat,
  });

  final VoidCallback onNewChat;
  final VoidCallback onJoinChat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.forum_outlined, size: 56, color: _vaultTextSoft),
          const SizedBox(height: 14),
          Text(
            'No Chats yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _vaultText,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start something new or step into an existing chat from an invite.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _vaultTextSoft, height: 1.4),
          ),
          const SizedBox(height: 22),
          _PrimaryGradientButton(
            text: 'New Group',
            icon: Icons.add_comment_rounded,
            onTap: onNewChat,
            bgA: _vaultPanel,
            bgB: _vaultPanelAlt,
            neonPink: _vaultPink,
            neonPurple: _vaultPurple,
          ),
          const SizedBox(height: 12),
          _SecondaryButton(
            text: 'Join Group',
            icon: Icons.group_add_rounded,
            onTap: onJoinChat,
            bg: _vaultPanel,
            outline: _vaultPurple.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }
}

class _MobileEmptyState extends StatelessWidget {
  const _MobileEmptyState({required this.onNewChat, required this.onJoinChat});

  final VoidCallback onNewChat;
  final VoidCallback onJoinChat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined, size: 56, color: _vaultTextSoft),
            const SizedBox(height: 12),
            Text(
              'No Chats yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _vaultText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Open a chat from Contacts or create a group and it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _vaultTextSoft),
            ),
            const SizedBox(height: 22),
            _PrimaryGradientButton(
              text: 'New Group',
              icon: Icons.add_comment_rounded,
              onTap: onNewChat,
              bgA: _vaultPanel,
              bgB: _vaultPanelAlt,
              neonPink: _vaultPink,
              neonPurple: _vaultPurple,
            ),
            const SizedBox(height: 12),
            _SecondaryButton(
              text: 'Join Group',
              icon: Icons.group_add_rounded,
              onTap: onJoinChat,
              bg: _vaultPanel,
              outline: _vaultPurple.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.white60,
            ),
            const SizedBox(height: 14),
            Text(
              'Nothing matches that search',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _vaultText,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a chat name, a person, or part of the latest message.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _vaultTextSoft),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Clear search'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.hintText});

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(color: _vaultText, fontWeight: FontWeight.w600),
      cursorColor: _vaultPink,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: _vaultTextSoft.withValues(alpha: 0.85)),
        prefixIcon: Icon(Icons.search_rounded, color: _vaultTextSoft, size: 20),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                onPressed: controller.clear,
                icon: Icon(
                  Icons.close_rounded,
                  color: _vaultTextSoft,
                  size: 18,
                ),
              ),
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.18),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: _vaultPink.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _CategoryFilterBar extends StatelessWidget {
  const _CategoryFilterBar({
    required this.categories,
    required this.selectedCategory,
    required this.onCategoryChanged,
  });

  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    if (categories.length <= 1) {
      return const SizedBox.shrink();
    }

    final isAll = selectedCategory == ChatThread.allCategory;
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        initialValue: selectedCategory,
        onSelected: onCategoryChanged,
        color: _vaultPanelAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        itemBuilder: (context) => categories
            .map(
              (category) => PopupMenuItem<String>(
                value: category,
                child: Row(
                  children: [
                    Icon(
                      category == selectedCategory
                          ? Icons.check_circle_rounded
                          : Icons.folder_outlined,
                      size: 18,
                      color: category == selectedCategory
                          ? _vaultPink
                          : Colors.white54,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        category == ChatThread.allCategory
                            ? 'All chats'
                            : category,
                        style: TextStyle(color: _vaultText),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(growable: false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isAll
                  ? Colors.white.withValues(alpha: 0.10)
                  : _vaultPink.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sell_outlined,
                size: 18,
                color: isAll ? Colors.white70 : _vaultPink,
              ),
              const SizedBox(width: 8),
              Text(
                isAll ? 'All chats' : selectedCategory,
                style: TextStyle(
                  color: _vaultText.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withValues(alpha: 0.66),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterToggle extends StatelessWidget {
  const _CategoryFilterToggle({
    required this.showFilters,
    required this.selectedCategory,
    required this.onTap,
  });

  final bool showFilters;
  final String selectedCategory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAll = selectedCategory == ChatThread.allCategory;
    final label = isAll ? 'Categories optional' : selectedCategory;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          foregroundColor: _vaultTextSoft,
        ),
        icon: Icon(
          showFilters ? Icons.folder_open_rounded : Icons.folder_outlined,
          size: 15,
        ),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 10.0,
            fontWeight: FontWeight.w700,
            color: _vaultTextSoft,
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.selected = false,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool selected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? _vaultText : _vaultTextSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 5),
            decoration: BoxDecoration(
              color: selected
                  ? _vaultPink.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              border: selected
                  ? Border.all(color: _vaultPink.withValues(alpha: 0.42))
                  : null,
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: foreground, size: 18),
                    if (badgeCount > 0)
                      Positioned(
                        right: -8,
                        top: -6,
                        child: _UnreadBadge(count: badgeCount),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 10.1,
                    fontWeight: FontWeight.w700,
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

class _PrimaryGradientButton extends StatelessWidget {
  const _PrimaryGradientButton({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.bgA,
    required this.bgB,
    required this.neonPink,
    required this.neonPurple,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final Color bgA;
  final Color bgB;
  final Color neonPink;
  final Color neonPurple;

  @override
  Widget build(BuildContext context) {
    final outerGlow = <BoxShadow>[
      BoxShadow(
        color: neonPink.withValues(alpha: 0.16),
        blurRadius: 30,
        spreadRadius: 2,
      ),
      BoxShadow(
        color: neonPurple.withValues(alpha: 0.10),
        blurRadius: 50,
        spreadRadius: 4,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: outerGlow,
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                child: Ink(
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [bgA, bgB],
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [
                                  neonPink.withValues(alpha: 0.14),
                                  neonPink.withValues(alpha: 0.06),
                                  Colors.transparent,
                                ],
                                stops: const [0.0, 0.30, 0.75],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 15, color: _vaultText),
                            const SizedBox(width: 7),
                            Text(
                              text,
                              style: TextStyle(
                                fontSize: 12.2,
                                fontWeight: FontWeight.w700,
                                color: _vaultText,
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
          ),
          IgnorePointer(
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: neonPink.withValues(alpha: 0.95),
                  width: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.text,
    required this.icon,
    required this.onTap,
    required this.bg,
    required this.outline,
  });

  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: outline, width: 1.35),
            ),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: _vaultText),
                  const SizedBox(width: 7),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w700,
                      color: _vaultText,
                    ),
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
