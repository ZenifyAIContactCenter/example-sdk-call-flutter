# Server push mẫu (APNs VoIP + FCM) — không có dependency npm, chỉ cần Node.
# Node ≥ 20.12: lib.mjs dùng process.loadEnvFile.
#
# Thư mục keys/ (AuthKey_<KeyID>.p8 + JSON service account) được CHÉP vào image tại /app/keys →
# image có chứa key: chỉ build trên máy chủ, KHÔNG push image lên registry. Đổi key → build lại.
# .env không vào image (.dockerignore chặn): truyền bằng env_file / --env-file.
# Xem README "Chạy bằng Docker".
FROM node:22-alpine

WORKDIR /app
COPY package.json *.mjs ./
# chown node + chỉ owner đọc: tránh lỗi EACCES khi file key trên máy chủ là root/600
COPY --chown=node:node keys/ ./keys/
# uuid webhook tự tạo lưu ở đây — docker-compose gắn volume để tạo lại container không mất
RUN chmod 500 keys && chmod 400 keys/* && mkdir -p /app/data && chown node:node /app/data

ENV NODE_ENV=production \
    # trong container phải nghe 0.0.0.0 mới publish cổng ra ngoài được (server.mjs mặc định
    # 127.0.0.1). Chỉ publish ra máy chủ: -p 127.0.0.1:3000:3000
    HOST=0.0.0.0 \
    PORT=3000

USER node
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- "http://127.0.0.1:${PORT}/health" >/dev/null || exit 1

# Mặc định: POST /push. Nghe webhook: `docker run … zenify-push node webhook.mjs`
CMD ["node", "server.mjs"]
