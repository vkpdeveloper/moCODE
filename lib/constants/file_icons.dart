import 'package:flutter/material.dart';
import 'package:simple_icons/simple_icons.dart';

/// Maps file extensions to their respective icons.
///
/// Uses [SimpleIcons] for brand-specific icons (programming languages, tools)
/// and falls back to [Icons] for generic file types where no brand icon exists
/// or is appropriate.
const Map<String, IconData> kFileExtensionIcons = {
  // Programming Languages
  'dart': SimpleIcons.dart,
  'py': SimpleIcons.python,
  'js': SimpleIcons.javascript,
  'ts': SimpleIcons.typescript,
  'jsx': SimpleIcons.react,
  'tsx': SimpleIcons.react,
  'html': SimpleIcons.html5,
  'htm': SimpleIcons.html5,
  'css': SimpleIcons.css3,
  'scss': SimpleIcons.sass,
  'sass': SimpleIcons.sass,
  'less': SimpleIcons.less,
  'java': SimpleIcons.java,
  'kt': SimpleIcons.kotlin,
  'kts': SimpleIcons.kotlin,
  'swift': SimpleIcons.swift,
  'c': SimpleIcons.c,
  'cpp': SimpleIcons.cplusplus,
  'h': SimpleIcons.c,
  'hpp': SimpleIcons.cplusplus,
  'cs': SimpleIcons.csharp,
  'go': SimpleIcons.go,
  'rb': SimpleIcons.ruby,
  'php': SimpleIcons.php,
  'rs': SimpleIcons.rust,
  'lua': SimpleIcons.lua,
  'pl': SimpleIcons.perl,
  'r': SimpleIcons.r,
  'scala': SimpleIcons.scala,
  'sh': SimpleIcons.gnubash,
  'bash': SimpleIcons.gnubash,
  'zsh': SimpleIcons.gnubash,
  'ps1': SimpleIcons.powershell,
  'bat': SimpleIcons.windows,
  'cmd': SimpleIcons.windows,

  // Data & Config Formats
  'json': SimpleIcons.json,
  'yaml': SimpleIcons.yaml,
  'yml': SimpleIcons.yaml,
  'xml': Icons.code, // No specific SimpleIcon for XML, using generic code
  'toml': SimpleIcons.toml,
  'ini': Icons.settings_applications,
  'env': Icons.settings,
  'gradle': SimpleIcons.gradle,
  'gitignore': SimpleIcons.git,
  'dockerfile': SimpleIcons.docker,
  'dockerignore': SimpleIcons.docker,
  'makefile': SimpleIcons.gnu,
  'cmake': SimpleIcons.cmake,

  // Documents
  'md': SimpleIcons.markdown,
  'markdown': SimpleIcons.markdown,
  'pdf': SimpleIcons.adobeacrobatreader,
  'doc': SimpleIcons.microsoftword,
  'docx': SimpleIcons.microsoftword,
  'xls': SimpleIcons.microsoftexcel,
  'xlsx': SimpleIcons.microsoftexcel,
  'ppt': SimpleIcons.microsoftpowerpoint,
  'pptx': SimpleIcons.microsoftpowerpoint,
  'txt': Icons.description,
  'csv': Icons.grid_on,

  // Images & Media
  'png': Icons.image,
  'jpg': Icons.image,
  'jpeg': Icons.image,
  'gif': Icons.gif,
  'svg': SimpleIcons.svg,
  'webp': Icons.image,
  'ico': Icons.image,
  'mp4': Icons.movie,
  'mov': Icons.movie,
  'avi': Icons.movie,
  'mp3': Icons.audiotrack,
  'wav': Icons.audiotrack,

  // Archives
  'zip': Icons.folder_zip,
  'tar': Icons.folder_zip,
  'gz': Icons.folder_zip,
  'rar': Icons.folder_zip,
  '7z': Icons.folder_zip,

  // Databases
  'sql': SimpleIcons
      .mysql, // Generic SQL often represented by DB icon, MySQL is a close proxy
  'sqlite': SimpleIcons.sqlite,
  'db': Icons.storage,
};

/// Retrieves the icon for a given file extension.
///
/// Returns `Icons.insert_drive_file` if no mapping is found.
/// The [extension] should not include the dot, but the function handles
/// it if provided.
IconData getIconForExtension(String extension) {
  final cleanExtension = extension.startsWith('.')
      ? extension.substring(1).toLowerCase()
      : extension.toLowerCase();

  return kFileExtensionIcons[cleanExtension] ?? Icons.insert_drive_file;
}
