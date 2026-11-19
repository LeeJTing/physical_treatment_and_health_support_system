# Veepoo Android SDK

Pinned vendor libraries for the K202 Pro and KS02 Pro Bluetooth adapter.
Source commit 26ebb0f7bbc2ada8a0374bd225b27b9eb1bfa89f.

The protocol library is 2.3.96.15 and the Bluetooth library is 1.20.
The other AARs are the vendor's required runtime dependencies. The vendor
repository's Apache 2.0 license is retained in this directory.

The adapter reads saved blood pressure and numerical glucose history using the reported firmware
capabilities and supports both legacy and newer daily-history protocols.
The app labels these records as watch estimates and asks for review before saving.
Users can enable automatic checking for a saved, per-account connection. Its
connection details and PIN are encrypted with an Android Keystore key.

Vendor source and API documentation are available in the
[HBandSDK repository](https://github.com/HBandSDK/Android_Ble_SDK).
