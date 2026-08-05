# Android release signing

GitHub Actions signs every release APK with one persistent release key. Create
the key once (do not put its passwords on the command line), then keep it backed
up:

```bash
keytool -genkeypair -v -keystore release.jks -storetype JKS \
  -keyalg RSA -keysize 4096 -validity 10000 -alias huginn
```

Add these repository Actions secrets:

- `ANDROID_KEYSTORE_BASE64` — the complete JKS/PKCS12 file encoded with
  `base64 -w 0 release.jks`;
- `ANDROID_KEYSTORE_PASSWORD` — keystore password;
- `ANDROID_KEY_ALIAS` — signing key alias;
- `ANDROID_KEY_PASSWORD` — signing key password.

Do not replace or delete the key after publishing an APK. Android accepts an
in-place update only when the application ID and signing certificate match and
the new `versionCode` is not lower than the installed one.

The workflow uses `GITHUB_RUN_NUMBER` as the Android `versionCode`, so every new
workflow run gets a monotonically increasing build number. A `vX.Y.Z` tag becomes
the APK `versionName`; a manual run keeps the version name from `pubspec.yaml`.

APKs produced by earlier Actions runs were signed with runner-local debug keys.
Those keys no longer exist, so such an installation must be removed once before
installing the first APK signed with the persistent release key.
