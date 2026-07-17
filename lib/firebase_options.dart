import 'package:firebase_core/firebase_core.dart';

/// Configuration used for receiving notifications on Android.
///
/// This set of options is used for receiving notifications
/// through the Zulip notification bouncer service:
///   https://zulip.readthedocs.io/en/latest/production/mobile-push-notifications.html
///
/// These values represent public identifiers for that service
/// as an application registered with the relevant Google service:
/// we deliver Android notifications through Firebase Cloud Messaging (FCM).
/// The values are derived from a `google-services.json` file.
/// For details, see:
///   https://developers.google.com/android/guides/google-services-plugin#processing_the_json_file
const kFirebaseOptionsAndroid = FirebaseOptions(
  // Right Angle's own Firebase project (`sid-personal`), so that our
  // self-hosted server can deliver notifications via FCM directly,
  // rather than through Zulip's notification bouncer.
  // Registered for package `dev.rightangle.chat`.
  appId: '1:${_RightAngleFirebaseOptions.projectNumber}:android:359191414dc129474f76d7',
  messagingSenderId: _RightAngleFirebaseOptions.projectNumber,
  projectId: _RightAngleFirebaseOptions.projectId,
  apiKey: _RightAngleFirebaseOptions.firebaseApiKey,
);

/// Configuration used for finding the notification token on iOS.
///
/// On iOS, we don't use Firebase to actually deliver notifications;
/// rather the Zulip notification bouncer service communicates with
/// the Apple Push Notification service (APNs) directly.
///
/// But we do use the Firebase library as a convenient binding to the
/// platform API for the setup steps of requesting the user's permission
/// to show notifications, and getting the token that the service uses
/// to represent that permission.
/// These values are similar to [kFirebaseOptionsAndroid] but are for iOS,
/// and they let us initialize the Firebase library so that we can do that.
///
/// TODO: Cut out Firebase for APNs and use a thinner platform-API binding.
///
/// TODO(iOS): No iOS app is registered in the `sid-personal` Firebase
///   project yet — this app currently ships Android-only.  Before building
///   for iOS, register an iOS app for the bundle ID and replace the `ios`
///   appId hash below.
const kFirebaseOptionsIos = FirebaseOptions(
  appId: '1:${_RightAngleFirebaseOptions.projectNumber}:ios:0000000000000000',
  messagingSenderId: _RightAngleFirebaseOptions.projectNumber,
  projectId: _RightAngleFirebaseOptions.projectId,
  apiKey: _RightAngleFirebaseOptions.firebaseApiKey,
);

abstract class _RightAngleFirebaseOptions {
  static const projectNumber = '386885828342';

  // Despite its value, this name applies across Android and iOS.
  static const projectId = 'sid-personal';

  // Despite the name, this Google Cloud "API key" is a very different kind
  // of thing from a Zulip "API key".  In particular, it's designed to be
  // included in published builds of client applications, and therefore
  // fundamentally public.  See docs:
  //   https://cloud.google.com/docs/authentication/api-keys
  //
  // Auto-created with the Android app registration in the `sid-personal`
  // Firebase project.  Like all Firebase Android API keys, it's designed to
  // be included in published client builds and is fundamentally public:
  //   https://cloud.google.com/docs/authentication/api-keys
  static const firebaseApiKey = 'AIzaSyA1nZ0sUbXl_iLk0FAXiJvdIXalE2pq7eU';
}
