/// Shared parse → resolve → insert for independent text/voice bookkeeping panels.
///
/// Reuses [parseBookkeepingText] and optional LLM enhancement; does not rewrite
/// the traditional keypad sheet.
library;

import '../../core/utils/money.dart';
import '../../data/db/centli_database.dart';
import 'ai_text_fill.dart';
import 'llm_text_fill.dart';

class SmartBookkeepingOutcome {
  const SmartBookkeepingOutcome({
    required this.ok,
    this.errorMessage,
    this.summary,
  });

  final bool ok;
  final String? errorMessage;
  final String? summary;

  factory SmartBookkeepingOutcome.fail(String message) =>
      SmartBookkeepingOutcome(ok: false, errorMessage: message);
}

/// Parse [rawText], resolve ledger entities, and insert a manual transaction.
Future<SmartBookkeepingOutcome> submitSmartBookkeepingText({
  required CentliDatabase db,
  required String rawText,
  required String ledgerId,
  required List<Account> accounts,
}) async {
  final raw = rawText.trim();
  if (raw.isEmpty) {
    return SmartBookkeepingOutcome.fail('请输入一句话或换种说法');
  }
  if (accounts.isEmpty) {
    return SmartBookkeepingOutcome.fail('请先添加账户后再记账');
  }

  final outCats = await db.loadCategories(ledgerId, 'out');
  final inCats = await db.loadCategories(ledgerId, 'in');
  final catRefs = <CategoryRef>[
    for (final c in outCats)
      CategoryRef(
        name: c.name,
        id: c.id,
        parentId: c.parentId,
        kind: c.kind,
      ),
    for (final c in inCats)
      CategoryRef(
        name: c.name,
        id: c.id,
        parentId: c.parentId,
        kind: c.kind,
      ),
  ];
  final allCatNames = catRefs.map((c) => c.name).toList();
  final accountNames = accounts.map((a) => a.name).toList();

  var parsed = parseBookkeepingText(
    raw,
    categoryNames: allCatNames,
    categories: catRefs,
    accountNames: accountNames,
  );

  try {
    final llmSettings = SmartFillLlmSettings();
    final cfg = await llmSettings.load(db);
    if (cfg.isReady) {
      final llm = await parseBookkeepingTextWithLlm(
        raw,
        config: cfg,
        categoryNames: allCatNames,
        categories: catRefs,
        accountNames: accountNames,
      );
      if (llm != null && llm.hasUsefulFill) {
        parsed = llm;
      }
    }
  } catch (_) {
    // Keep local parse; never block save on LLM errors.
  }

  if (!parsed.hasUsefulFill) {
    return SmartBookkeepingOutcome.fail('未能识别，请换种说法或用手动记账');
  }

  final type = parsed.type ?? 'out';
  final amount = parsed.amount;
  if (amount == null || amount <= 0) {
    return SmartBookkeepingOutcome.fail('未能识别金额，请换种说法或用手动记账');
  }

  List<Category> cats = outCats;
  if (type == 'in') {
    cats = inCats;
  } else if (type != 'transfer') {
    cats = outCats;
  }

  String? categoryId;
  var categoryResolved = false;
  if (parsed.hasConfidentCategory && type != 'transfer') {
    Category? hit;
    for (final c in cats) {
      if (c.name == parsed.categoryName) {
        hit = c;
        break;
      }
    }
    hit ??= () {
      for (final c in cats) {
        if (c.name.contains(parsed.categoryName!) ||
            parsed.categoryName!.contains(c.name)) {
          return c;
        }
      }
      return null;
    }();
    if (hit != null) {
      categoryId = hit.id;
      categoryResolved = true;
    }
  }

  if (parsed.merchant != null &&
      parsed.merchant!.trim().isNotEmpty &&
      type != 'transfer') {
    final key = parsed.merchant!.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final rule = await db.findMerchantRule(ledgerId, key);
    if (rule?.categoryId != null) {
      final id = rule!.categoryId!;
      if (cats.any((c) => c.id == id)) {
        categoryId = id;
        categoryResolved = true;
      }
    }
  }

  String? accountId = accounts.first.id;
  String? toAccountId = accounts.length > 1 ? accounts[1].id : null;
  if (parsed.accountName != null) {
    for (final a in accounts) {
      if (a.name == parsed.accountName) {
        accountId = a.id;
        break;
      }
    }
  }
  if (parsed.toAccountName != null) {
    for (final a in accounts) {
      if (a.name == parsed.toAccountName) {
        toAccountId = a.id;
        break;
      }
    }
  }
  if (parsed.merchant != null && parsed.merchant!.trim().isNotEmpty) {
    final key = parsed.merchant!.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final rule = await db.findMerchantRule(ledgerId, key);
    if (rule?.accountId != null &&
        accounts.any((a) => a.id == rule!.accountId) &&
        parsed.accountName == null) {
      accountId = rule!.accountId;
    }
  }

  if (type == 'transfer') {
    if (toAccountId == null) {
      return SmartBookkeepingOutcome.fail('未能识别转入账户，请用手动记账');
    }
    if (toAccountId == accountId) {
      return SmartBookkeepingOutcome.fail('转出与转入账户不能相同');
    }
  } else if (!categoryResolved || categoryId == null) {
    return SmartBookkeepingOutcome.fail('未能识别分类，请换种说法或用手动记账');
  }

  Account? account;
  for (final a in accounts) {
    if (a.id == accountId) {
      account = a;
      break;
    }
  }
  final currency = account?.currency ?? 'CNY';
  final amountMinor = toMinor(currency, amount);
  final leftover = parsed.note?.trim();
  final note = (leftover != null && leftover.isNotEmpty) ? leftover : null;
  final merchantText = parsed.merchant?.trim();
  final merchant =
      (merchantText != null && merchantText.isNotEmpty) ? merchantText : null;

  int? toAmountMinor;
  if (type == 'transfer') {
    Account? toAcc;
    for (final a in accounts) {
      if (a.id == toAccountId) {
        toAcc = a;
        break;
      }
    }
    final toCcy = toAcc?.currency ?? currency;
    if (toCcy == currency) {
      toAmountMinor = amountMinor;
    } else {
      return SmartBookkeepingOutcome.fail(
        '跨币种转账请用手动记账填写对方金额或汇率',
      );
    }
  }

  await db.insertManualTransaction(
    ledgerId: ledgerId,
    type: type,
    amountMinor: amountMinor,
    currency: currency,
    accountId: accountId!,
    toAccountId: type == 'transfer' ? toAccountId : null,
    categoryId: type == 'transfer' ? null : categoryId,
    merchant: merchant,
    note: note,
    happenAt: parsed.happenAt,
    toAmountMinor: toAmountMinor,
  );

  final summary = parsed.hits.isEmpty
      ? '已记账'
      : '已记账：${parsed.hits.join(' · ')}';
  return SmartBookkeepingOutcome(ok: true, summary: summary);
}
