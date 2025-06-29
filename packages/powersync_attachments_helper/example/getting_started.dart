import 'dart:async';

import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:powersync_core/powersync_core.dart';

const schema = Schema([
  Table('users', [Column.text('name'), Column.text('photo_id')])
]);

// Assume PowerSync database is initialized elsewhere
late PowerSyncDatabase db;
// Assume remote storage is implemented elsewhere
late AbstractRemoteStorageAdapter remoteStorage;
late PhotoAttachmentQueue attachmentQueue;

class PhotoAttachmentQueue extends AbstractAttachmentQueue {
  PhotoAttachmentQueue(
      PowerSyncDatabase db, AbstractRemoteStorageAdapter remoteStorage)
      : super(db: db, remoteStorage: remoteStorage);

  @override
  Future<Attachment> saveFile(String fileId, int size,
      {String mediaType = 'image/jpeg'}) async {
    String filename = '$fileId.jpg';
    Attachment photoAttachment = Attachment(
      id: fileId,
      filename: filename,
      state: AttachmentState.queuedUpload.index,
      mediaType: mediaType,
      localUri: getLocalFilePathSuffix(filename),
      size: size,
    );

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  Future<Attachment> deleteFile(String fileId) async {
    String filename = '$fileId.jpg';
    Attachment photoAttachment = Attachment(
        id: fileId,
        filename: filename,
        state: AttachmentState.queuedDelete.index);

    return attachmentsService.saveAttachment(photoAttachment);
  }

  @override
  StreamSubscription<void> watchIds({String? fileExtension}) {
    return db.watch('''
      SELECT photo_id FROM users
      WHERE photo_id IS NOT NULL
    ''').map((results) {
      return results.map((row) => row['photo_id'] as String).toList();
    }).listen((ids) async {
      List<String> idsInQueue = await attachmentsService.getAttachmentIds();
      List<String> relevantIds =
          ids.where((element) => !idsInQueue.contains(element)).toList();
      syncingService.processIds(relevantIds, fileExtension);
    });
  }
}

Future<void> initializeAttachmentQueue(PowerSyncDatabase db) async {
  attachmentQueue = PhotoAttachmentQueue(db, remoteStorage);
  await attachmentQueue.init();
}
