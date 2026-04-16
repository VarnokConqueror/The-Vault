import '../../state/chat_store.dart';
import '../../state/contacts_store.dart';
import '../../state/identity_store.dart';
import '../../state/vault_peer_store.dart';
import 'vault_models.dart';

String resolveDirectPeerId({
  required String directPeerHint,
  required String senderId,
  String? sourceUserId,
}) {
  final myId = IdentityStore.publicId.trim();
  final cleanHint = directPeerHint.trim();
  final cleanSender = senderId.trim();
  final cleanSource = (sourceUserId ?? '').trim();

  if (cleanHint.isNotEmpty && cleanHint != myId) {
    return cleanHint;
  }
  if (cleanSender.isNotEmpty && cleanSender != myId) {
    return cleanSender;
  }
  if (cleanSource.isNotEmpty && cleanSource != myId) {
    return cleanSource;
  }
  return '';
}

Future<String> resolveIncomingVaultChatId({
  required String rawChatId,
  required String directPeerHint,
  required String senderId,
  required String senderName,
  String? sourceUserId,
  String? currentContactId,
  String? currentChatTitle,
  VaultAddress? sourceAddress,
  String? fallbackChatId,
}) async {
  final cleanRawChatId = rawChatId.trim();
  final peerId = resolveDirectPeerId(
    directPeerHint: directPeerHint,
    senderId: senderId,
    sourceUserId: sourceUserId,
  );

  if (peerId.isEmpty) {
    if (cleanRawChatId.isEmpty) {
      return (fallbackChatId ?? '').trim();
    }
    final existingChat = ChatStore.getChat(cleanRawChatId);
    if (existingChat != null) {
      return existingChat.id;
    }
    final chat = await ChatStore.upsertChatFromInvite(
      chatId: cleanRawChatId,
      title: ChatStore.defaultChatTitle,
    );
    return chat.id;
  }

  final knownContact = ContactsStore.getById(peerId);
  final existingName = (knownContact?.displayName ?? '').trim();
  final currentContact = (currentContactId ?? '').trim();
  final currentTitle = (currentChatTitle ?? '').trim();
  final cleanSenderName = senderName.trim();
  final titleHint = currentContact == peerId && currentTitle.isNotEmpty
      ? currentTitle
      : existingName.isNotEmpty
      ? existingName
      : cleanSenderName.isNotEmpty
      ? cleanSenderName
      : 'Direct Chat';

  if (knownContact == null) {
    await ContactsStore.addContact(publicId: peerId, displayName: titleHint);
  }
  if (sourceAddress != null) {
    await VaultPeerStore.setForContact(contactId: peerId, address: sourceAddress);
  }
  final chat = await ChatStore.createChatForContact(
    contactId: peerId,
    title: titleHint,
  );
  return chat.id;
}
