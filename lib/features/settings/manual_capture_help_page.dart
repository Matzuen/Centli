import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';

/// Help for the three manual pending-capture paths when send-out
/// (red packet / transfer) has no system notification.
class ManualCaptureHelpPage extends StatelessWidget {
  const ManualCaptureHelpPage({super.key});

  static const sampleUrl =
      'centli://pending?text=%E5%90%91%E5%BC%A0%E4%B8%89%E8%BD%AC%E8%B4%A6%E6%88%90%E5%8A%9F%20%C2%A520.00';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        );

    return CentliGradientScaffold(
      appBar: AppBar(title: const Text('发出去没通知？')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            '微信/支付宝「发出去的红包、转账」常常没有系统通知，通知监听无法捕获。'
            '可用下面三种方式手动加入「待确认」队列（与自动记账同一队列）。',
            style: bodyStyle,
          ),
          const SizedBox(height: CentliSpacing.sectionLoose),
          _section(
            context,
            icon: Icons.share_outlined,
            title: '1. 分享账单文字 / 图片到 Centli',
            children: [
              Text(
                '在微信「账单」或支付宝「账单」详情页，使用系统分享，选择 Centli。\n'
                '· 分享文字：自动解析金额/商户后进入待确认。\n'
                '· 分享图片：走截图 OCR 识别后再入队。\n'
                '冷启动分享也会打开待确认页。',
                style: bodyStyle,
              ),
              const SizedBox(height: CentliSpacing.item),
              Text(
                '提示：Android 已支持分享接收；iOS 系统分享扩展将在后续版本补充，'
                '目前可用剪贴板或快捷指令 URL。',
                style: bodyStyle,
              ),
            ],
          ),
          _section(
            context,
            icon: Icons.document_scanner_outlined,
            title: '2. 从截图识别',
            children: [
              Text(
                '在「待确认」或「自动记账」页点「从截图识别」，从相册或相机选取账单截图。'
                '识别在设备本地完成（中文 OCR），不会上传图片。',
                style: bodyStyle,
              ),
            ],
          ),
          _section(
            context,
            icon: Icons.link_outlined,
            title: '3. 快捷指令 / URL / 剪贴板',
            children: [
              Text(
                'URL 示例：\n'
                'centli://pending?text=向张三转账成功 ¥20.00\n'
                '或：\n'
                'centli://pending?amount=20&merchant=张三&note=红包\n\n'
                'Android / iOS 快捷指令可：\n'
                '1) 复制账单文字 → 打开 App →「从剪贴板导入」；或\n'
                '2) 将文字 URL 编码后拼进 centli://pending?text=... 并打开。',
                style: bodyStyle,
              ),
              const SizedBox(height: CentliSpacing.item),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(const ClipboardData(text: sampleUrl));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制示例链接')),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('复制示例链接'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return CentliSoftCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(CentliSpacing.cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: CentliSpacing.item),
            ...children,
          ],
        ),
      ),
    );
  }
}
