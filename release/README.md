# Release output

Run `npm run package:release` from the repository root to build and verify the
Windows and Android applications, create the Windows installer, copy the signed
APK, and generate SHA-256 checksum files in this directory.

Packaging deliberately refuses to continue unless the established Android
release key is already present under `.release-secrets/` and referenced by the
ignored `android/key.properties` file. Back up that private key securely. Every
future Android update must use the same key; the release script will never
silently replace it.
