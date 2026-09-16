import 'package:flutter/material.dart';

/// 我的 Tab（阶段 0）：备份/同步/应用锁/主题设置按 W9/W13–W15 接入
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.cloud_upload_outlined),
            title: Text('备份与同步'),
            subtitle: Text('WebDAV 自主同步 · W13 上线'),
          ),
          ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('应用锁'),
            subtitle: Text('PIN / 生物识别 · W14 上线'),
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('主题'),
            subtitle: Text('明暗 / 字体 · W9 上线'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于素页'),
            subtitle: Text('本地优先的图文记录工具 · v0.1.0'),
          ),
        ],
      ),
    );
  }
}