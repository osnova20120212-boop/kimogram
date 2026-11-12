# Kimogram for Android

Kimogram for Android is Telegram Android (`DrKLO/Telegram`, GPL v2) at the commit in
`UPSTREAM_COMMIT`, changed by `apply.sh`:

- `patches/*.patch` - edits to upstream files (`git apply`, in order).
- `overlay/` - new files and replaced images, copied over the tree.
- package name `com.kimogram.app`, API keys from the `TELEGRAM_API_ID` / `TELEGRAM_API_HASH`
  secrets, our package added to `google-services.json`.

`.github/workflows/android.yml` builds the Play bundle (`Kimogram.aab`), turns it into an
installable universal `Kimogram.apk` with bundletool (one native build instead of two) and
publishes both as a GitHub Release `android-build-<n>`.

## Working on it

```sh
git clone https://github.com/DrKLO/Telegram tg && cd tg && git checkout $(cat ../android/UPSTREAM_COMMIT)
TELEGRAM_API_ID=1 TELEGRAM_API_HASH=0 ../android/apply.sh .
# edit upstream files, then regenerate the patch (excluding files apply.sh writes itself):
git diff -- . ':!*google-services.json' ':!*.png' ':!*.webp' ':!TMessagesProj/src/main/res/drawable/icon_background*.xml' \
  ':!TMessagesProj/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml' > ../android/patches/0001-kimogram-base.patch
```

and reset `APP_ID`/`APP_HASH`/`APP_PACKAGE` in the patch to the upstream values (apply.sh sets them).

## What is changed and why

- Branding: `KimogramBrand` rewrites "Telegram" to "Kimogram" in every string read through
  `LocaleController` (built-in and cloud language packs), except Telegram's own services
  (Premium, Stars, Business, Gateway, Passport), "the Telegram app" (where login codes arrive)
  and addresses. App name resource is "Kimogram".
- Icon: the iOS icon (`Telegram/Telegram-iOS/Telegram.icon/Assets/Logo.png`) as an adaptive icon,
  the transparent mark as its foreground and themed (monochrome) layer. `tools/make_icons.py`
  regenerates every size. The alternative-icon picker is hidden (those icons carry Telegram's logo).
- Google Play rules for forks: billing off (`IS_BILLING_UNAVAILABLE`), no self-update check,
  passkeys and Firebase phone verification off (official app ids only), SafetyNet key empty.
- Account type and contact MIME types use our package so Kimogram installs next to Telegram.
- Notifications: a third-party api_id gets no Firebase pushes, so the notification service and
  background connection are on unless the user turns them off.
