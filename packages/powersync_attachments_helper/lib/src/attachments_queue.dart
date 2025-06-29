import 'dart:async';

import './attachments_queue_table.dart';
import './attachments_service.dart';
import './local_storage_adapter.dart';
import './remote_storage_adapter.dart';
import './syncing_service.dart';
import 'package:logging/logging.dart';
import 'package:powersync_core/powersync_core.dart';

/// Logger for the attachment queue
final log = Logger('AttachmentQueue');

/// Abstract class used to implement the attachment queue
/// Requires a PowerSyncDatabase, an implementation of
/// AbstractRemoteStorageAdapter and an attachment directory name which will
/// determine which folder attachments are stored into.
abstract class AbstractAttachmentQueue {
  PowerSyncDatabase db;
  AbstractRemoteStorageAdapter remoteStorage;
  String attachmentDirectoryName;
  late AttachmentsService attachmentsService;
  late SyncingService syncingService;
  final LocalStorageAdapter localStorage = LocalStorageAdapter();
  String attachmentsQueueTableName;

  /// Function to handle errors when downloading attachments
  /// Return true if you want to ignore attachment
  Future<bool> Function(Attachment attachment, Object exception)?
      onDownloadError;

  /// Function to handle errors when uploading attachments
  /// Return true if you want to ignore attachment
  Future<bool> Function(Attachment attachment, Object exception)? onUploadError;

  /// Interval in minutes to periodically run [syncingService.startPeriodicSync]
  /// Default is 5 minutes
  int intervalInMinutes;

  /// Provide the subdirectories located on external storage so that they are created
  /// when the attachment queue is initialized.
  List<String>? subdirectories;

  /// File extension to be used for the attachments queue
  /// Can be left null if no extension is used or if extension is part of the filename
  String? fileExtension;

  AbstractAttachmentQueue(
      {required this.db,
      required this.remoteStorage,
      this.attachmentDirectoryName = 'attachments',
      this.attachmentsQueueTableName = defaultAttachmentsQueueTableName,
      this.onDownloadError,
      this.onUploadError,
      this.intervalInMinutes = 5,
      this.subdirectories,
      this.fileExtension}) {
    attachmentsService = AttachmentsService(
        db, localStorage, attachmentDirectoryName, attachmentsQueueTableName);
    syncingService = SyncingService(
        db, remoteStorage, localStorage, attachmentsService, getLocalUri,
        onDownloadError: onDownloadError, onUploadError: onUploadError);
  }

  /// Create watcher to get list of ID's from a table to be used for syncing in the attachment queue.
  /// Set the file extension if you are using a different file type
  StreamSubscription<void> watchIds({String? fileExtension});

  /// Create a function to save files using the attachment queue
  Future<Attachment> saveFile(String fileId, int size);

  /// Create a function to delete files using the attachment queue
  Future<Attachment> deleteFile(String fileId);

  /// Initialize the attachment queue by
  /// 1. Creating attachments directory
  /// 2. Adding watches for uploads, downloads, and deletes
  /// 3. Adding trigger to run uploads, downloads, and deletes when device is online after being offline
  Future<void> init() async {
    // Ensure the directory where attachments are downloaded, exists
    await localStorage.makeDir(await getStorageDirectory());

    if (subdirectories != null) {
      for (String subdirectory in subdirectories!) {
        await localStorage
            .makeDir('${await getStorageDirectory()}/$subdirectory');
      }
    }

    watchIds(fileExtension: fileExtension);
    syncingService.watchAttachments();
    syncingService.startPeriodicSync(intervalInMinutes);

    db.statusStream.listen((status) {
      if (db.currentStatus.connected) {
        _trigger();
      }
    });
  }

  Future<void> _trigger() async {
    await syncingService.runSync();
  }

  /// Returns the local file path for the given filename, used to store in the database.
  /// Example: filename: "attachment-1.jpg" returns "attachments/attachment-1.jpg"
  String getLocalFilePathSuffix(String filename) {
    return '$attachmentDirectoryName/$filename';
  }

  /// Returns the directory where attachments are stored on the device, used to make dir
  /// Example: "/var/mobile/Containers/Data/Application/.../Library/attachments/"
  Future<String> getStorageDirectory() async {
    String userStorageDirectory = await localStorage.getUserStorageDirectory();
    return '$userStorageDirectory/$attachmentDirectoryName';
  }

  /// Return users storage directory with the attachmentPath use to load the file.
  /// Example: filePath: "attachments/attachment-1.jpg" returns "/var/mobile/Containers/Data/Application/.../Library/attachments/attachment-1.jpg"
  Future<String> getLocalUri(String filePath) async {
    String storageDirectory = await getStorageDirectory();
    return '$storageDirectory/$filePath';
  }
}
