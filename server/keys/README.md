# keys/

Thả 2 file key vào thư mục này — server (Node hoặc Docker) tự nhận, không cần khai đường dẫn:

| File | Dùng cho | Lấy ở đâu |
| --- | --- | --- |
| `AuthKey_<KeyID>.p8` | iOS — APNs VoIP. Key ID lấy luôn từ tên file | developer.apple.com → Keys |
| `*.json` (service account) | Android — FCM | Firebase → Project settings → Service accounts |

Giữ đúng tên file `.p8` Apple tải về (`AuthKey_XXXXXXXXXX.p8`). Mỗi loại chỉ để **một** file.
Vẫn cần `APN_TEAM_ID` (và `APN_BUNDLE_ID` nếu khác app demo) trong `.env`.

Mọi file trong thư mục này (trừ README) đã nằm trong `.gitignore` — không bị commit. Docker **chép**
thư mục này vào image (`/app/keys`) lúc build: đổi key → `docker compose up -d --build`, không push image
lên registry. Trên máy chủ nên `chmod 600 keys/*`.
