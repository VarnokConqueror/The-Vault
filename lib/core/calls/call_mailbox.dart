String directCallMailboxId({
  required String localUserId,
  required String peerUserId,
}) {
  final local = localUserId.trim();
  final peer = peerUserId.trim();
  if (local.isEmpty || peer.isEmpty) return '';

  final ordered = <String>[local, peer]..sort();
  return 'call:${ordered[0]}::${ordered[1]}';
}

String callInboxMailboxId(String userId) {
  final id = userId.trim();
  if (id.isEmpty) return '';
  return 'call-inbox:$id';
}
