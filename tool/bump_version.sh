#!/bin/bash
# Đổi version app demo theo dạng 1.0.x — giống run_version.sh của app RN.
#   ./tool/bump_version.sh          1.0.2+3 → 1.0.3+1  (version mới → build về 1)
#   ./tool/bump_version.sh 1.0.7    → 1.0.7+1          (đặt version, build về 1)
#   ./tool/bump_version.sh build    1.0.2+3 → 1.0.2+4  (giữ version, build +1 — upload lại)
# Đổi đồng thời:
#  · `version:` trong pubspec.yaml → Android versionName; versionCode = major·10⁶ + minor·10⁴
#    + patch·100 + build (android/app/build.gradle.kts) nên vẫn luôn tăng dù build về 1
#  · MARKETING_VERSION / CURRENT_PROJECT_VERSION trong project Xcode (= Version / Build ở tab
#    General) → iOS CFBundleShortVersionString / CFBundleVersion (Info.plist đọc 2 biến này,
#    nên Archive bằng Xcode hay `flutter build ipa` đều ra cùng version).
set -e

cd "$(dirname "$0")/.."
PUBSPEC="pubspec.yaml"
IOS_FILE="ios/Runner.xcodeproj/project.pbxproj"

CURRENT=$(grep -E '^version:' "$PUBSPEC" | sed -E 's/^version:[[:space:]]*//')
if ! [[ "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)\+([0-9]+)$ ]]; then
  echo "❌ version trong $PUBSPEC phải dạng 1.0.x+N (đang là '$CURRENT')"
  exit 1
fi
MAJOR=${BASH_REMATCH[1]}; MINOR=${BASH_REMATCH[2]}; PATCH=${BASH_REMATCH[3]}; BUILD=${BASH_REMATCH[4]}
OLD_NAME="$MAJOR.$MINOR.$PATCH"

if [ "$1" = "build" ]; then
  NAME="$OLD_NAME"
elif [ -n "$1" ]; then
  if ! [[ "$1" =~ ^([0-9]+)\.([0-9]{1,2})\.([0-9]{1,2})$ ]]; then
    echo "❌ Version phải dạng 1.0.x, minor / patch ≤ 99 (nhận '$1')"
    exit 1
  fi
  NAME="$1"
else
  NAME="$MAJOR.$MINOR.$((PATCH + 1))"
fi

# version mới → build về 1; cùng version → build +1
if [ "$NAME" = "$OLD_NAME" ]; then BUILD=$((BUILD + 1)); else BUILD=1; fi
if [ "$BUILD" -gt 99 ]; then
  echo "❌ Build tối đa 99 mỗi version (versionCode Android dành 2 chữ số cho build)"
  exit 1
fi
IFS=. read -r MA MI PA <<< "$NAME"
VERSION_CODE=$((MA * 1000000 + MI * 10000 + PA * 100 + BUILD))

echo "📦 Cũ: $CURRENT"

perl -pi -e "s/^version:.*/version: $NAME+$BUILD/" "$PUBSPEC"
perl -pi -e "s/MARKETING_VERSION = \d+\.\d+\.\d+;/MARKETING_VERSION = $NAME;/g" "$IOS_FILE"
perl -pi -e "s/CURRENT_PROJECT_VERSION = \d+;/CURRENT_PROJECT_VERSION = $BUILD;/g" "$IOS_FILE"

echo "✅ Android versionName → $NAME, versionCode → $VERSION_CODE"
echo "✅ iOS Version → $NAME, Build → $BUILD"

# Sinh lại ios/Flutter/Generated.xcconfig (FLUTTER_BUILD_NAME/NUMBER + DART_DEFINES) cho Archive bằng Xcode.
flutter build ios --config-only --release --dart-define-from-file=dart_defines.local.json >/dev/null 2>&1 ||
  { echo "❌ flutter build ios --config-only lỗi — chạy tay để xem chi tiết"; exit 1; }
echo "✅ ios/Flutter/Generated.xcconfig đã cập nhật (Xcode → Product → Archive dùng được ngay)"
echo "🎉 version: $NAME+$BUILD"
