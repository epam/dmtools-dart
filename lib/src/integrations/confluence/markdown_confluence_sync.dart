/// Synchronizes a local Markdown directory tree with a Confluence page
/// subtree — port of the Java `MarkdownConfluenceSync`.
///
/// Markdown files become child pages (an `index.md`/`readme.md` becomes the
/// directory's own page body), non-Markdown files become attachments, and
/// links between Markdown files are rewritten to Confluence page links.
/// The class is stateless apart from the collaborators it receives, so it
/// unit-tests without a live Confluence instance.
library;

import 'dart:convert';
import 'dart:io';

import 'confluence_markdown.dart';

/// Page CRUD callbacks used by [MarkdownConfluenceSync].
abstract class ConfluencePageOperations {
  /// Creates a page under [parentId] in [space]; returns its JSON object.
  Map<String, dynamic> createPage(
    String title,
    String parentId,
    String body,
    String space,
  );

  /// Updates page [contentId] (title/parent/body/space); returns its JSON.
  Map<String, dynamic> updatePage(
    String contentId,
    String title,
    String parentId,
    String body,
    String space, [
    String historyComment = '',
  ]);

  /// Lists the direct child page objects of [contentId].
  List<Map<String, dynamic>> getChildren(String contentId);

  /// Deletes the page [contentId]; returns the raw response text.
  String deletePage(String contentId);

  /// Fetches page [contentId] with its title + ancestors expanded.
  Map<String, dynamic> getContent(String contentId);
}

/// Attachment callbacks used by [MarkdownConfluenceSync].
abstract class SyncAttachmentHelper {
  /// Lists the file names already attached to the page [contentId].
  List<String> listAttachmentNames(String contentId);

  /// Uploads [file] to the page [contentId] (skip when already present).
  void uploadAttachment(String contentId, File file);
}

/// One Markdown file inside a synced directory.
class _FileNode {
  final File file;
  String title = '';
  String contentId = '';

  _FileNode(this.file);
}

/// One directory inside a synced tree.
class _DirNode {
  final Directory dir;
  String title;
  File? indexFile;
  final files = <_FileNode>[];
  final subdirs = <_DirNode>[];
  final attachments = <File>[];
  String contentId = '';
  String? parentId;

  _DirNode(this.dir, this.title);
}

final _mdLink = RegExp(r'\[([^\]]*)\]\(([^)]+)\)', dotAll: true);
final _h1 = RegExp('^#\\s+(.+)\$', multiLine: true);
final _imageAttachment = RegExp(
    r'<ac:image[^>]*>.*?<ri:attachment[^>]*ri:filename="([^"]+)".*?>.*?</ac:image>',
    dotAll: true);
final _linkAttachment = RegExp(
    r'<ac:link[^>]*>.*?<ri:attachment[^>]*ri:filename="([^"]+)".*?>.*?</ac:link>',
    dotAll: true);

/// Drives a [ConfluencePageOperations]/[SyncAttachmentHelper] pair to mirror
/// a local Markdown tree into Confluence.
class MarkdownConfluenceSync {
  final SyncAttachmentHelper _attachments;
  final ConfluencePageOperations _pageOps;

  /// Creates a sync engine over the given collaborators.
  MarkdownConfluenceSync(this._attachments, this._pageOps);

  /// Synchronizes [rootDir] under the Confluence page [parentId] in [space].
  ///
  /// When [deleteOrphans] is set, child pages of [parentId] whose titles are
  /// not present in the local tree are deleted recursively. [attachmentsDir]
  /// overrides where referenced attachments are read from (defaults to each
  /// Markdown file's own directory). Returns a JSON summary string.
  String syncDirectory(
    Directory rootDir,
    String parentId,
    String space,
    bool deleteOrphans,
    String? attachmentsDir,
  ) {
    final root = _buildDirTree(rootDir);
    final pathToTitle = _buildPathToTitleMap(rootDir, root);
    final expectedTitles = pathToTitle.values.toSet();
    root.contentId = parentId;
    _preserveRootMetadata(root, parentId);
    _syncDirNode(root, rootDir, pathToTitle, space, attachmentsDir);
    final deleted =
        deleteOrphans ? _deleteOrphanPages(parentId, expectedTitles) : const [];
    return jsonEncode({
      'rootDirectory': rootDir.absolute.path,
      'parentId': parentId,
      'expectedPages': expectedTitles.length,
      'syncedPages': expectedTitles.toList()..sort(),
      'deleted': deleted,
    });
  }

  /// Fetches the root page's real title/parent so the update in place does
  /// not rename it to the local folder name (Java `syncDirectory`).
  void _preserveRootMetadata(_DirNode root, String parentId) {
    try {
      final existing = _pageOps.getContent(parentId);
      final ancestors = existing['ancestors'] as List?;
      if (ancestors != null && ancestors.isNotEmpty) {
        root.parentId =
            (ancestors.last as Map<String, dynamic>)['id']?.toString();
      }
      final title = existing['title']?.toString() ?? '';
      if (title.isNotEmpty) root.title = title;
    } on Object {
      // Non-fatal: proceed with directory-name title / self-parent fallback.
    }
  }

  /// Syncs one directory node: its own page body, file pages, then subdirs.
  void _syncDirNode(
    _DirNode node,
    Directory rootDir,
    Map<String, String> pathToTitle,
    String space,
    String? attachmentsDir,
  ) {
    String folderBody;
    Set<String> referenced = const {};
    if (node.indexFile != null) {
      final processed = _processMarkdownLinks(
          _readFile(node.indexFile!), rootDir, node.indexFile!, pathToTitle);
      folderBody = markdownToConfluenceStorage(processed);
      referenced = extractAttachmentReferences(processed);
      _uploadReferencedAttachments(
          node.contentId, processed, node.indexFile!.parent, attachmentsDir);
    } else {
      folderBody = '<p>${escapeXml(node.title)}</p>';
    }
    final uploaded = _uploadDirectoryAttachments(node, referenced);
    folderBody = _appendAttachmentLinks(folderBody, uploaded);
    _pageOps.updatePage(node.contentId, node.title,
        node.parentId ?? node.contentId, folderBody, space);

    for (final fileNode in node.files) {
      _syncFileNode(
          fileNode, node, rootDir, pathToTitle, space, attachmentsDir);
    }
    for (final subdir in node.subdirs) {
      final folderPage = _findOrCreateChildPage(subdir.title, node.contentId,
          space, '<p>${escapeXml(subdir.title)}</p>');
      subdir.contentId = folderPage['id']?.toString() ?? '';
      subdir.parentId = node.contentId;
      _syncDirNode(subdir, rootDir, pathToTitle, space, attachmentsDir);
    }
  }

  /// Syncs one Markdown file to a child page of its directory node.
  void _syncFileNode(
    _FileNode fileNode,
    _DirNode node,
    Directory rootDir,
    Map<String, String> pathToTitle,
    String space,
    String? attachmentsDir,
  ) {
    final processed = _processMarkdownLinks(
        _readFile(fileNode.file), rootDir, fileNode.file, pathToTitle);
    final storage = markdownToConfluenceStorage(processed);
    final page = _findOrCreateChildPage(
        fileNode.title, node.contentId, space, '<p>Placeholder</p>');
    final pageId = page['id']?.toString() ?? '';
    _uploadReferencedAttachments(
        pageId, processed, fileNode.file.parent, attachmentsDir);
    _pageOps.updatePage(pageId, fileNode.title, node.contentId, storage, space);
    fileNode.contentId = pageId;
  }

  /// Uploads every attachment referenced from [markdown] found in [baseDir].
  void _uploadReferencedAttachments(
    String pageId,
    String markdown,
    Directory baseDir,
    String? attachmentsDir,
  ) {
    final dir = _resolveAttachmentsDir(baseDir, attachmentsDir);
    final existing = _attachments.listAttachmentNames(pageId).toSet();
    for (final name in extractAttachmentReferences(markdown)) {
      if (existing.contains(name)) continue;
      final file = File('${dir.path}/$name');
      if (file.existsSync()) _attachments.uploadAttachment(pageId, file);
    }
  }

  /// Uploads the directory's loose non-Markdown files that are not already
  /// referenced inline; returns the names that were newly uploaded.
  List<String> _uploadDirectoryAttachments(
    _DirNode node,
    Set<String> referenced,
  ) {
    final uploaded = <String>[];
    final existing = _attachments.listAttachmentNames(node.contentId).toSet();
    for (final attachment in node.attachments) {
      final name = attachment.uri.pathSegments.last;
      if (existing.contains(name) || referenced.contains(name)) continue;
      try {
        _attachments.uploadAttachment(node.contentId, attachment);
        uploaded.add(name);
      } on Object {
        // A failed attachment upload must not abort the page sync.
      }
    }
    return uploaded;
  }

  /// Returns the child page with [title], creating it when absent.
  Map<String, dynamic> _findOrCreateChildPage(
    String title,
    String parentId,
    String space,
    String placeholderBody,
  ) {
    for (final child in _pageOps.getChildren(parentId)) {
      if (child['title'] == title) return child;
    }
    return _pageOps.createPage(title, parentId, placeholderBody, space);
  }

  /// Deletes children of [parentId] whose titles are not in [expectedTitles].
  List<String> _deleteOrphanPages(String parentId, Set<String> expectedTitles) {
    final deleted = <String>[];
    for (final child in _pageOps.getChildren(parentId)) {
      if (!expectedTitles.contains(child['title'])) {
        _deleteRecursively(child, deleted);
      }
    }
    return deleted;
  }

  /// Deletes [content] and its subtree, recording titles into [deleted].
  void _deleteRecursively(Map<String, dynamic> content, List<String> deleted) {
    final id = content['id']?.toString() ?? '';
    for (final child in _pageOps.getChildren(id)) {
      _deleteRecursively(child, deleted);
    }
    _pageOps.deletePage(id);
    deleted.add(content['title']?.toString() ?? id);
  }

  /// Builds the directory tree model from [dir].
  _DirNode _buildDirTree(Directory dir) {
    final node = _DirNode(dir, _dirBaseName(dir));
    final children = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    for (final child in children) {
      if (child is Directory) {
        node.subdirs.add(_buildDirTree(child));
      } else if (child is File) {
        _classifyFile(node, child);
      }
    }
    return node;
  }

  /// Routes [file] to the index slot, the file list, or the attachments.
  void _classifyFile(_DirNode node, File file) {
    final lower = _baseName(file.path).toLowerCase();
    if (lower.endsWith('.md')) {
      if (lower == 'index.md' || lower == 'readme.md') {
        node.indexFile = file;
      } else {
        node.files.add(_FileNode(file));
      }
    } else {
      node.attachments.add(file);
    }
  }

  /// Builds the relative-path → page-title map for link rewriting.
  Map<String, String> _buildPathToTitleMap(Directory rootDir, _DirNode node) {
    final map = <String, String>{};
    _fillPathToTitle(rootDir, node, map);
    return map;
  }

  /// Recursive worker for [_buildPathToTitleMap].
  void _fillPathToTitle(
    Directory rootDir,
    _DirNode node,
    Map<String, String> map,
  ) {
    final dirRel = _relativePath(rootDir, node.dir);
    if (dirRel.isNotEmpty) map[dirRel] = node.title;
    if (node.indexFile != null) {
      map[_relativePath(rootDir, node.indexFile!)] = node.title;
    }
    for (final fileNode in node.files) {
      fileNode.title = _extractTitle(_readFile(fileNode.file), fileNode.file);
      map[_relativePath(rootDir, fileNode.file)] = fileNode.title;
    }
    for (final subdir in node.subdirs) {
      _fillPathToTitle(rootDir, subdir, map);
    }
  }

  /// Rewrites relative `.md` links in [markdown] (read from [currentFile])
  /// to the target page's title.
  String _processMarkdownLinks(
    String markdown,
    Directory rootDir,
    File currentFile,
    Map<String, String> pathToTitle,
  ) {
    if (markdown.trim().isEmpty) return markdown;
    return markdown.replaceAllMapped(_mdLink, (m) {
      final url = m.group(2)!.trim();
      if (_skippableLink(url)) return m[0]!;
      final candidate =
          File('${currentFile.parent.path}/${url.split('#').first}');
      if (!candidate.existsSync()) return m[0]!;
      final target = candidate.resolveSymbolicLinksSync();
      final title = pathToTitle[_relativePath(rootDir, File(target))];
      if (title == null) return m[0]!;
      return '[${m.group(1)}]($title)';
    });
  }

  /// Whether a link destination must not be rewritten.
  bool _skippableLink(String url) =>
      url.isEmpty ||
      isExternalUrl(url) ||
      url.startsWith('#') ||
      !url.toLowerCase().endsWith('.md');

  /// Extracts a page title: first `# Heading`, else the file base name.
  String _extractTitle(String markdown, File file) {
    final m = _h1.firstMatch(markdown);
    if (m != null) return m.group(1)!.trim();
    var name = _baseName(file.path);
    if (name.toLowerCase().endsWith('.md')) {
      name = name.substring(0, name.length - 3);
    }
    return name;
  }

  /// Chooses the attachments source directory.
  Directory _resolveAttachmentsDir(Directory baseDir, String? attachmentsDir) {
    if (attachmentsDir != null && attachmentsDir.trim().isNotEmpty) {
      return Directory(attachmentsDir);
    }
    return baseDir;
  }

  /// Appends an `<h2>Attachments</h2>` list for not-yet-linked [names].
  String _appendAttachmentLinks(String storageBody, List<String> names) {
    final linkable = names
        .where(
            (name) => !_referencedAttachmentNames(storageBody).contains(name))
        .toList();
    if (linkable.isEmpty) return storageBody;
    final buf = StringBuffer('<h2>Attachments</h2><ul>');
    for (final name in linkable) {
      buf.write('<li><ac:link><ri:attachment ri:filename="'
          '${escapeXml(name)}" /><ac:link-body>${escapeXml(name)}'
          '</ac:link-body></ac:link></li>');
    }
    return '$storageBody${buf.toString()}</ul>';
  }

  /// Collects attachment names already referenced from a storage body.
  Set<String> _referencedAttachmentNames(String storageBody) => {
        for (final m in _imageAttachment.allMatches(storageBody)) m.group(1)!,
        for (final m in _linkAttachment.allMatches(storageBody)) m.group(1)!,
      };

  /// Reads [file] as UTF-8 text.
  String _readFile(File file) => file.readAsStringSync(encoding: utf8);

  /// Path of [file] relative to [rootDir], `/`-separated (or absolute).
  String _relativePath(Directory rootDir, FileSystemEntity file) {
    final root = rootDir.resolveSymbolicLinksSync();
    final abs = file.resolveSymbolicLinksSync();
    if (abs == root) return '';
    final prefix = '$root/';
    if (abs.startsWith(prefix)) return abs.substring(prefix.length);
    return abs;
  }

  /// Final path segment of [path].
  String _baseName(String path) => path.split(Platform.pathSeparator).last;

  /// Final path segment of [dir]'s path.
  String _dirBaseName(Directory dir) => _baseName(dir.path);
}
