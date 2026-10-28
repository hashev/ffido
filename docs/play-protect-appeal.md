# Запрос пересмотра классификации Play Protect — FFIDO

Черновик для владельца, не отправлен. Дата подготовки: 2026-10-28.
Форма: https://support.google.com/googleplay/android-developer/answer/2992033

Перед отправкой подтвердить SHA-256 файла на телефоне, версию Android, канал,
дату появления и текст «Подробнее». Прикрепить обрезанный снимок системного
предупреждения без сообщений/персональных данных из фона. Приложить отчёт
`<apk>.audit.json`, созданный `scripts/release/android_audit.py`. Если фактический
файл отличается, заменить сведения ниже; не отправлять данные чужого APK.

## Текст обращения (English)

Please review the Play Protect classification of FFIDO. A user reports a
“Harmful app blocked” warning on a Pixel 6a while updating from version 1.0.3
to 1.0.4 through FFIDO's in-app update flow. We have not yet confirmed the
SHA-256 of the exact file on the device or the specific PHA category, so we
are requesting a classification review rather than claiming a proven false positive.

Official candidate release:

- Package: `io.github.hashev.ffido`
- Version: `1.0.4`, versionCode: `1019`
- APK: https://github.com/hashev/ffido/releases/download/v1.0.4/ffido-v1.0.4-client-android-universal.apk
- SHA-256: `3b5a867af40d60dad8d98dc63fbb21ccd8f0245563d04a6a2663bdeac3e6c39c`
- Signing certificate SHA-256: `61f1f10c15f8d3724dfe19938f9923ed2878dd9c81113c90489aded29af3fbd0`
- Source commit: `4da3372d57ae9da50490d6187a4733a4a8596827`
- Source: https://github.com/hashev/ffido

The official APK passes apksigner verification (APK signature scheme v2), has
minSdk 24 and targetSdk 36, and is not debuggable or testOnly. Its packaged release
identity matches the release commit. Structural checks did not identify an
unexpected sensitive permission or an unprotected exported updater receiver.
These checks are limited and do not establish an antivirus verdict.

FFIDO is a FidoNet client distributed through GitHub Releases. Its update flow
uses INTERNET and REQUEST_INSTALL_PACKAGES to update its own package after a
user action. It verifies a signed update manifest, the downloaded APK size and
SHA-256, matching package name and signing certificate, and increasing versionCode.
Installation uses Android PackageInstaller and system user confirmation; it does
not silently install arbitrary third-party packages. The updater permission and
Android updater implementation were unchanged between source tags v1.0.3 and v1.0.4.

Please identify the relevant classification or behavior requiring correction,
and reconsider the warning if the submitted official APK is incorrectly classified.
We will provide the device-specific details and verified artifact hash with this request.

## Что ещё не проверено

- Фактический APK на Pixel и его совпадение с официальным candidate.
- Проверка Play Protect на конечном исправленном выпуске.
- Полный анализ всех зависимостей/native-кода на отсутствие вредоносности.

APK, обращения и приватные QA fixtures автоматически никуда не отправлялись.
