import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../../core/services/bilibili_service.dart';

typedef BiliAddCallback = FutureOr<void> Function(
    Map<String, dynamic> metadata);
typedef BiliPlayCallback = FutureOr<void> Function(
    BiliVideo video, BiliPart part);
typedef BiliQrBuilder = Widget Function(BuildContext context, String loginUrl);

/// Supply qrBuilder: (_, value) => QrImageView(data: value, size: 224).
/// The caller owns an injected service; this view owns a service it creates.
class BilibiliAccountView extends StatefulWidget {
  final BilibiliService? service;
  final BiliQrBuilder qrBuilder;
  final BiliAddCallback onAdd;
  final BiliPlayCallback? onPlay;
  const BilibiliAccountView(
      {super.key,
      this.service,
      required this.qrBuilder,
      required this.onAdd,
      this.onPlay});

  @override
  State<BilibiliAccountView> createState() => _BilibiliAccountViewState();
}

class _BilibiliAccountViewState extends State<BilibiliAccountView> {
  late final BilibiliService _service = widget.service ?? BilibiliService();
  final _search = TextEditingController();
  Timer? _timer;
  BiliQrLogin? _qr;
  String _status = '未登录';
  String? _error;
  bool _busy = true;
  bool _polling = false;
  bool _changingProtection = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _service.initialize();
      await _service.refreshAccount();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _login() async {
    _timer?.cancel();
    setState(() {
      _busy = true;
      _error = null;
      _qr = null;
    });
    try {
      final qr = await _service.createQrLogin();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _status = '等待扫码';
      });
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll(qr));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _poll(BiliQrLogin qr) async {
    if (_polling || !identical(_qr, qr)) return;
    _polling = true;
    try {
      final status = await _service.pollQrLogin(qr);
      if (!mounted || !identical(_qr, qr)) return;
      setState(() {
        _error = null;
        _status = switch (status) {
          BiliQrStatus.waiting => '等待扫码',
          BiliQrStatus.scanned => '已扫码，等待确认',
          BiliQrStatus.expired => '二维码已过期',
          BiliQrStatus.authenticated => '已登录',
        };
        if (status == BiliQrStatus.expired ||
            status == BiliQrStatus.authenticated) {
          _timer?.cancel();
          _qr = null;
        }
      });
    } catch (error) {
      // A network failure stops automatic polling. Restarting is explicit.
      _timer?.cancel();
      if (mounted && identical(_qr, qr)) {
        setState(() {
          _error = _message(error);
          _qr = null;
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _logout() async {
    if (!await _confirm(context, '退出此设备上的 B 站账号？')) {
      return;
    }
    _timer?.cancel();
    setState(() {
      _busy = true;
      _qr = null;
      _error = null;
      _status = '未登录';
    });
    try {
      await _service.logout();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _transferLogin({required bool exporting}) async {
    if (!await _confirm(context, exporting ? '导出敏感登录信息？' : '导入 B站登录信息？',
        detail: exporting
            ? '文件包含可用于登录账号的明文 Cookie。仅保存在可信设备，不要分享或上传。'
            : '只选择可信的登录 JSON / Cookie 文件。联网验证成功后才替换当前账号，并重新开启只读保护。')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    _timer?.cancel();
    _service.cancelQrLogin();
    _qr = null;
    try {
      if (exporting) {
        final value = await _service.exportLogin();
        final path = await FilePicker.platform.saveFile(
            dialogTitle: '保存敏感登录文件',
            fileName: 'bilibili-login-private.json',
            type: FileType.custom,
            allowedExtensions: ['json'],
            bytes: utf8.encode(value));
        if (path != null &&
            !kIsWeb &&
            (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          await File(path).writeAsString(value, flush: true);
        }
      } else {
        final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['json', 'txt'],
            withData: true);
        if (result == null) return;
        final bytes = result.files.single.bytes;
        if (bytes == null || bytes.length > 65536) {
          throw const FormatException('请选择小于 64 KB 的登录文件');
        }
        await _service.importLogin(utf8.decode(bytes));
        _status = '已登录';
      }
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _protection(bool value) async {
    if (!value &&
        !await _confirm(context, '关闭账号只读保护？',
            detail: '关闭后可操作点赞、投币、收藏和关注，每次操作仍需单独确认。')) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _changingProtection = true;
      _error = null;
    });
    try {
      await _service.setReadOnly(value);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _changingProtection = false);
    }
  }

  void _browse(String title, Future<BiliPage<Object>> Function(int, int) loader,
      {List<String> sorts = const []}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _BiliBrowser(
            title: title,
            service: _service,
            loader: loader,
            sorts: sorts,
            onAdd: widget.onAdd,
            onPlay: widget.onPlay)));
  }

  void _submitSearch() {
    final input = _search.text.trim();
    try {
      BilibiliService.parseInput(input);
    } catch (error) {
      setState(() => _error = _message(error));
      return;
    }
    setState(() => _error = null);
    _browse(
        input,
        (page, order) => _service.search(input,
            page: page, order: BiliSearchOrder.values[order]),
        sorts: const ['综合排序', '最多播放', '最新发布', '最多收藏']);
  }

  @override
  Widget build(BuildContext context) {
    final account = _service.account;
    return Scaffold(
      appBar: AppBar(title: const Text('哔哩哔哩'), actions: [
        PopupMenuButton<bool>(
            tooltip: '登录信息迁移',
            enabled: !_busy,
            icon: const Icon(Icons.import_export),
            onSelected: (exporting) => _transferLogin(exporting: exporting),
            itemBuilder: (_) => [
                  const PopupMenuItem(value: false, child: Text('导入登录信息')),
                  if (account != null)
                    const PopupMenuItem(value: true, child: Text('导出登录信息')),
                ]),
        IconButton(
            onPressed: _busy ? null : _load,
            tooltip: '刷新账号',
            icon: const Icon(Icons.refresh)),
      ]),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) _ErrorNotice(message: _error!),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _Avatar(account?.avatar ?? ''),
            title: Text(account?.name ?? 'B 站账号'),
            subtitle: Text(account == null
                ? _status
                : '账号编号：${account.mid}${account.vip ? ' | 大会员' : ''}'),
            trailing: account == null
                ? null
                : IconButton(
                    onPressed: _busy ? null : _logout,
                    tooltip: '退出此设备上的账号',
                    icon: const Icon(Icons.logout))),
        if (account == null) ...[
          if (_qr != null) ...[
            Center(
                child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: SizedBox.square(
                        dimension: 224,
                        child: widget.qrBuilder(context, _qr!.url)))),
            const SizedBox(height: 12),
            Center(child: Text(_status)),
          ],
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: _busy ? null : _login,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(_qr == null ? '扫码登录' : '刷新二维码'))),
        ],
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
                _service.readOnly ? Icons.shield_outlined : Icons.lock_open),
            title: const Text('账号只读保护'),
            value: _service.readOnly,
            onChanged: _changingProtection || _busy ? null : _protection),
        const Divider(height: 28),
        TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submitSearch(),
            decoration: InputDecoration(
                labelText: '关键词、BV号或视频链接',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    onPressed: _submitSearch,
                    tooltip: '搜索',
                    icon: const Icon(Icons.arrow_forward)))),
        const SizedBox(height: 16),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('我的收藏夹'),
            trailing: const Icon(Icons.chevron_right),
            enabled: account != null,
            onTap: () => _browse('我的收藏夹', (page, _) async {
                  final folders = await _service.getFavoriteFolders();
                  return BiliPage(folders,
                      page: 1, total: folders.length, hasMore: false);
                })),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.people_outline),
            title: const Text('我的关注'),
            trailing: const Icon(Icons.chevron_right),
            enabled: account != null,
            onTap: () => _browse(
                '我的关注', (page, _) => _service.getFollowings(page: page))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('订阅的合集'),
            trailing: const Icon(Icons.chevron_right),
            enabled: account != null,
            onTap: () => _browse('订阅的合集',
                (page, _) => _service.getSubscribedCollections(page: page))),
      ])),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_qr != null) _service.cancelQrLogin();
    _service.removeListener(_refresh);
    if (widget.service == null) _service.dispose();
    _search.dispose();
    super.dispose();
  }
}

String _message(Object error) =>
    error is BiliException ? error.message : '操作未完成，请稍后重试。';

Future<bool> _confirm(BuildContext context, String title,
        {String? detail}) async =>
    await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: detail == null ? null : Text(detail),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('确认')),
                ])) ??
    false;

class _ErrorNotice extends StatelessWidget {
  final String message;
  const _ErrorNotice({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(message,
          style: TextStyle(color: Theme.of(context).colorScheme.error)));
}

class _Avatar extends StatelessWidget {
  final String url;
  const _Avatar(this.url);
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: 44,
      child: url.isEmpty
          ? const Icon(Icons.person_outline)
          : ClipOval(
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.person_outline))));
}

class _BiliBrowser extends StatefulWidget {
  final String title;
  final BilibiliService service;
  final Future<BiliPage<Object>> Function(int page, int sort) loader;
  final List<String> sorts;
  final BiliAddCallback onAdd;
  final BiliPlayCallback? onPlay;
  const _BiliBrowser(
      {required this.title,
      required this.service,
      required this.loader,
      required this.onAdd,
      this.onPlay,
      this.sorts = const []});
  @override
  State<_BiliBrowser> createState() => _BiliBrowserState();
}

class _BiliBrowserState extends State<_BiliBrowser> {
  final _items = <Object>[];
  bool _busy = true;
  bool _more = false;
  int _page = 0;
  int _sort = 0;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    final generation = reset ? ++_generation : _generation;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _busy = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 0;
      }
    });
    try {
      final result = await widget.loader(page, _sort);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items.addAll(result.items);
        _page = page;
        _more = result.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  void _open(Object item) {
    Widget page;
    if (item is BiliVideo) {
      page = _BiliVideoDetails(
          service: widget.service,
          bvid: item.bvid,
          onAdd: widget.onAdd,
          onPlay: widget.onPlay);
    } else if (item is BiliUploader) {
      page = _BiliUploaderView(
          uploader: item,
          service: widget.service,
          onAdd: widget.onAdd,
          onPlay: widget.onPlay);
    } else if (item is BiliCollection) {
      page = _BiliBrowser(
          title: item.title,
          service: widget.service,
          loader: (page, sort) => widget.service.getCollectionVideos(
              item.ownerMid, item.id,
              page: page, reverse: sort == 1),
          sorts: const ['默认顺序', '倒序排列'],
          onAdd: widget.onAdd,
          onPlay: widget.onPlay);
    } else if (item is BiliFavoriteFolder) {
      page = _BiliBrowser(
          title: item.title,
          service: widget.service,
          loader: (page, sort) => widget.service.getFavoriteVideos(item.id,
              page: page, order: const ['mtime', 'view', 'pubtime'][sort]),
          sorts: const ['最近收藏', '最多播放', '最新发布'],
          onAdd: widget.onAdd,
          onPlay: widget.onPlay);
    } else {
      return;
    }
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _tile(Object item) {
    var title = '';
    var subtitle = '';
    var image = '';
    IconData fallback = Icons.video_library_outlined;
    if (item is BiliVideo) {
      title = item.title;
      subtitle = '${item.ownerName} | ${item.bvid}';
      image = item.cover;
    }
    if (item is BiliUploader) {
      title = item.name;
      subtitle = '用户编号：${item.mid}';
      image = item.avatar;
      fallback = Icons.person_outline;
    }
    if (item is BiliCollection) {
      title = item.title;
      subtitle = '${item.count} 个视频';
      image = item.cover;
    }
    if (item is BiliFavoriteFolder) {
      title = item.title;
      subtitle = '${item.count} 个视频';
      fallback = Icons.folder_outlined;
    }
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: SizedBox(
            width: 72,
            height: 48,
            child: image.isEmpty
                ? Icon(fallback)
                : Image.network(image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(fallback))),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(item));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title:
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
                onPressed: _busy ? null : () => _load(reset: true),
                tooltip: '刷新',
                icon: const Icon(Icons.refresh)),
          ]),
      body: Column(children: [
        if (widget.sorts.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DropdownButtonFormField<int>(
                  initialValue: _sort,
                  decoration: const InputDecoration(labelText: '排序方式'),
                  items: List.generate(
                      widget.sorts.length,
                      (i) => DropdownMenuItem(
                          value: i, child: Text(widget.sorts[i]))),
                  onChanged: _busy
                      ? null
                      : (value) {
                          _sort = value ?? 0;
                          _load(reset: true);
                        })),
        if (_busy) const LinearProgressIndicator(),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _items.length + 1,
                    itemBuilder: (context, index) {
                      if (index < _items.length) return _tile(_items[index]);
                      return Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(children: [
                            if (_error != null) ...[
                              _ErrorNotice(message: _error!),
                              IconButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _load(reset: _page == 0),
                                  tooltip: '重试',
                                  icon: const Icon(Icons.refresh)),
                            ] else if (!_busy && _items.isEmpty)
                              const Text('暂无内容'),
                            if (_more && !_busy && _error == null)
                              TextButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.expand_more),
                                  label: const Text('加载更多')),
                          ]));
                    }))),
      ]));
}

class _BiliUploaderView extends StatelessWidget {
  final BiliUploader uploader;
  final BilibiliService service;
  final BiliAddCallback onAdd;
  final BiliPlayCallback? onPlay;
  const _BiliUploaderView(
      {required this.uploader,
      required this.service,
      required this.onAdd,
      this.onPlay});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title:
              Text(uploader.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            _AccountCommands(service: service, ownerMid: uploader.mid)
          ]),
      body: ListView(children: [
        ListTile(
            leading: _Avatar(uploader.avatar),
            title: Text(uploader.name),
            subtitle: Text('用户编号：${uploader.mid}')),
        if (uploader.description.isNotEmpty)
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(uploader.description)),
        ListTile(
            leading: const Icon(Icons.video_library_outlined),
            title: const Text('投稿视频'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => _BiliBrowser(
                        title: uploader.name,
                        service: service,
                        loader: (page, order) => service.getUploaderVideos(
                            uploader.mid,
                            page: page,
                            order: BiliUploaderOrder.values[order]),
                        sorts: const ['最新发布', '最多播放', '最多收藏'],
                        onAdd: onAdd,
                        onPlay: onPlay)))),
        ListTile(
            leading: const Icon(Icons.playlist_play),
            title: const Text('视频合集'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => _BiliBrowser(
                        title: '视频合集',
                        service: service,
                        loader: (page, _) =>
                            service.getCollections(uploader.mid, page: page),
                        onAdd: onAdd,
                        onPlay: onPlay)))),
      ]));
}

class _BiliVideoDetails extends StatefulWidget {
  final BilibiliService service;
  final String bvid;
  final BiliAddCallback onAdd;
  final BiliPlayCallback? onPlay;
  const _BiliVideoDetails(
      {required this.service,
      required this.bvid,
      required this.onAdd,
      this.onPlay});
  @override
  State<_BiliVideoDetails> createState() => _BiliVideoDetailsState();
}

class _BiliVideoDetailsState extends State<_BiliVideoDetails> {
  late Future<BiliVideo> _video = widget.service.getVideo(widget.bvid);
  final _pending = <int>{};
  final _added = <int>{};
  bool _playing = false;

  Future<void> _act(BiliVideo video, BiliPart part, {bool play = false}) async {
    if (_pending.contains(part.cid) || (play && _playing)) return;
    setState(() {
      _pending.add(part.cid);
      if (play) _playing = true;
    });
    try {
      if (play) {
        await widget.onPlay!(video, part);
      } else {
        await widget.onAdd(video.toSourceData(part: part, compact: true));
        _added.add(part.cid);
      }
      if (mounted && !play) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已加入学习列表')));
      }
    } on BiliException catch (error) {
      if (mounted && error.kind != BiliErrorKind.cancelled) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _pending.remove(part.cid);
          if (play) _playing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.bvid)),
      body: FutureBuilder<BiliVideo>(
          future: _video,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        _ErrorNotice(message: _message(snapshot.error!)),
                        IconButton(
                            onPressed: () => setState(() =>
                                _video = widget.service.getVideo(widget.bvid)),
                            tooltip: '重试',
                            icon: const Icon(Icons.refresh)),
                      ])));
            }
            final video = snapshot.data;
            if (video == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(children: [
              if (video.cover.isNotEmpty)
                Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.network(video.cover,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined))))),
              ListTile(
                  title: Text(video.title),
                  subtitle: Text(video.ownerName),
                  trailing: _AccountCommands(
                      service: widget.service,
                      aid: video.aid,
                      ownerMid: video.ownerMid),
                  onTap: video.ownerMid <= 0
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => _BiliUploaderView(
                                  uploader: BiliUploader(
                                      mid: video.ownerMid,
                                      name: video.ownerName,
                                      avatar: ''),
                                  service: widget.service,
                                  onAdd: widget.onAdd,
                                  onPlay: widget.onPlay)))),
              if (video.description.isNotEmpty)
                Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(video.description)),
              const Divider(),
              for (final part in video.parts)
                ListTile(
                    title: Text('P${part.page}  ${part.title}'),
                    subtitle: Text(
                        '${part.duration.inMinutes}:${part.duration.inSeconds.remainder(60).toString().padLeft(2, '0')}'),
                    trailing: SizedBox(
                        width: widget.onPlay == null ? 48 : 96,
                        height: 48,
                        child: Row(children: [
                          if (widget.onPlay != null)
                            IconButton(
                                tooltip: '播放此分P',
                                icon: const Icon(Icons.play_arrow),
                                onPressed:
                                    _pending.contains(part.cid) || _playing
                                        ? null
                                        : () => _act(video, part, play: true)),
                          IconButton(
                              tooltip: _added.contains(part.cid)
                                  ? '已加入学习列表'
                                  : '将此分P加入学习列表',
                              icon: Icon(_added.contains(part.cid)
                                  ? Icons.playlist_add_check
                                  : Icons.playlist_add),
                              onPressed: _pending.contains(part.cid) ||
                                      _added.contains(part.cid)
                                  ? null
                                  : () => _act(video, part)),
                        ]))),
            ]);
          }));
}

class _AccountCommands extends StatefulWidget {
  final BilibiliService service;
  final int? aid;
  final int ownerMid;
  const _AccountCommands(
      {required this.service, this.aid, required this.ownerMid});
  @override
  State<_AccountCommands> createState() => _AccountCommandsState();
}

const _accountCommandLabels = {
  'Like': '点赞',
  'Unlike': '取消点赞',
  'Add 1 coin': '投 1 枚硬币',
  'Add 2 coins': '投 2 枚硬币',
  'Favorite': '收藏',
  'Remove favorite': '取消收藏',
  'Follow': '关注',
  'Unfollow': '取消关注',
};

class _AccountCommandsState extends State<_AccountCommands> {
  bool _busy = false;
  Future<void> _command(String command) async {
    final label = _accountCommandLabels[command]!;
    setState(() => _busy = true);
    try {
      int? folderId;
      if (command == 'Favorite' || command == 'Remove favorite') {
        final folders = await widget.service.getFavoriteFolders();
        if (!mounted) return;
        if (folders.isEmpty) {
          throw const BiliException('此账号暂无收藏夹。');
        }
        folderId = await showDialog<int>(
            context: context,
            builder: (context) =>
                SimpleDialog(title: const Text('选择收藏夹'), children: [
                  for (final folder in folders)
                    SimpleDialogOption(
                        onPressed: () => Navigator.pop(context, folder.id),
                        child: Text(folder.title))
                ]));
        if (folderId == null) return;
      }
      if (!mounted ||
          !await _confirm(context, '确认在 B 站$label？',
              detail: command.contains('coin')
                  ? '投出的硬币无法退回。若请求超时，操作可能已成功，请先核实再重试。'
                  : null)) {
        return;
      }
      switch (command) {
        case 'Like':
          await widget.service.setLiked(widget.aid!, true);
        case 'Unlike':
          await widget.service.setLiked(widget.aid!, false);
        case 'Add 1 coin':
          await widget.service.addCoins(widget.aid!);
        case 'Add 2 coins':
          await widget.service.addCoins(widget.aid!, count: 2);
        case 'Favorite':
          await widget.service
              .updateFavorite(widget.aid!, addFolderIds: [folderId!]);
        case 'Remove favorite':
          await widget.service
              .updateFavorite(widget.aid!, removeFolderIds: [folderId!]);
        case 'Follow':
          await widget.service.setFollowing(widget.ownerMid, true);
        case 'Unfollow':
          await widget.service.setFollowing(widget.ownerMid, false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$label成功')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.service,
      builder: (context, _) {
        final enabled =
            !widget.service.readOnly && widget.service.isLoggedIn && !_busy;
        return PopupMenuButton<String>(
            enabled: enabled,
            onSelected: _command,
            tooltip: widget.service.readOnly ? '账号只读保护已开启' : '账号操作',
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.more_vert),
            itemBuilder: (_) => [
                  for (final command in [
                    if (widget.aid != null) ...[
                      'Like',
                      'Unlike',
                      'Add 1 coin',
                      'Add 2 coins',
                      'Favorite',
                      'Remove favorite',
                    ],
                    if (widget.ownerMid > 0) ...['Follow', 'Unfollow'],
                  ])
                    PopupMenuItem(
                        value: command,
                        child: Text(_accountCommandLabels[command]!)),
                ]);
      });
}
