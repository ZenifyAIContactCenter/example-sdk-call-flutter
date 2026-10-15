package vn.zenify.zenify_call_example

import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import vn.zenify.zenify_call.ZenifyCallPush

/**
 * Service FCM DUY NHẤT của app (thay service của firebase_messaging — xem manifest).
 * Push cuộc gọi → zenify_call xử lý native NGAY (kể cả khi app đã bị tắt, không chờ Dart);
 * push còn lại → firebase_messaging như bình thường (onMessage / onBackgroundMessage ở Dart).
 *
 * App Flutter thật làm y hệt: hai FirebaseMessagingService cùng nhận MESSAGING_EVENT
 * thì chỉ MỘT cái chạy — nên kế thừa thay vì khai thêm.
 */
class AppMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        if (ZenifyCallPush.handle(applicationContext, remoteMessage.data)) return
        super.onMessageReceived(remoteMessage)
    }
}
