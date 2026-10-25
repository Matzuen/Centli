/// Display helpers for asset-account labels.
///
/// Transfer paths and account rows use **账本名-账户名** so cross-ledger
/// transfers stay readable (never a bare UUID).
String formatLedgerAccountLabel({
  required String accountName,
  String? ledgerName,
}) {
  final a = accountName.trim();
  final l = (ledgerName ?? '').trim();
  if (a.isEmpty) return l;
  if (l.isEmpty) return a;
  return '$l-$a';
}
