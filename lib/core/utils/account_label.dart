/// Display helpers for asset-account labels.
///
/// Only **cross-ledger** flows should pass [includeLedger]=true so the label
/// is `账本名-账户名`. Same-ledger list/detail rows keep the bare account name.
String formatLedgerAccountLabel({
  required String accountName,
  String? ledgerName,
  bool includeLedger = false,
}) {
  final a = accountName.trim();
  final l = (ledgerName ?? '').trim();
  if (a.isEmpty) return includeLedger ? l : '';
  if (!includeLedger || l.isEmpty) return a;
  return '$l-$a';
}
