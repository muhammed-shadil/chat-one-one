import 'package:cloud_functions/cloud_functions.dart';

import '../config.dart';
import '../models/admin_photo.dart';

/// Loads the admin page's photos, given the admin password.
typedef PhotoLoader = Future<AdminPhotoList> Function(String password);

/// A reason the photos couldn't be loaded, worded for the admin page.
class AdminException implements Exception {
  const AdminException(this.message, {this.wrongPassword = false});

  final String message;
  final bool wrongPassword;

  @override
  String toString() => message;
}

/// Talks to this chat's admin Cloud Function ([kAdminPhotosFunction]:
/// `adminPhotos`, or `adminPhotos2` for the second chat; functions/index.js).
/// The archive is hidden from the app by the security rules; this function
/// is the only way in, and it checks the chat's own admin password.
class AdminService {
  AdminService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: kFunctionsRegion);

  final FirebaseFunctions _functions;

  Future<AdminPhotoList> listPhotos(String password) async {
    try {
      final result = await _functions
          .httpsCallable(kAdminPhotosFunction)
          .call<Object?>({'password': password});
      return AdminPhotoList.fromData(result.data);
    } on FirebaseFunctionsException catch (e) {
      throw switch (e.code) {
        'permission-denied' =>
          const AdminException('Wrong password.', wrongPassword: true),
        'failed-precondition' => const AdminException(
            'The admin password has not been set up yet. See "Admin page" in the README.'),
        'not-found' || 'unimplemented' => const AdminException(
            'The admin functions are not deployed yet. See "Admin page" in the README.'),
        'unavailable' || 'deadline-exceeded' =>
          const AdminException('No connection. Check the internet and try again.'),
        _ => AdminException('Could not load the photos (${e.code}). ${e.message ?? ''}'.trim()),
      };
    }
  }
}
