# Release output

Run `npm run package:release` from the repository root to build and verify the
Windows and Android applications, create the Windows installer, copy the signed
APK, and generate SHA-256 checksum files in this directory.

The first run creates the Android signing key under `.release-secrets/` and its
ignored `android/key.properties` file. Back up that private key securely. Every
future Android update must use the same key.
