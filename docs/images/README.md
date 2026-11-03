# Демонстрации Android для README

GIF записаны с настоящих экранов FFIDO, на Android API 35. Отдельная точка входа
`apps/frontend/tool/readme_demo.dart` подставляет вымышленные письма через существующий
тестовый транспорт. Она не подключается к серверу и не входит в обычный запуск
`lib/main.dart`. В ролике Netmail показано создание черновика, без отправки.

Для повторной записи используйте одноразовый Android-эмулятор: демонстрационный
APK имеет тот же application ID, что и обычное приложение. Нужны Flutter из
[основной инструкции](../../README.md), Android SDK (`adb`) и FFmpeg.

```sh
cd apps/frontend
flutter pub get
flutter build apk --debug --no-pub --target tool/readme_demo.dart
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5554 shell wm size 900x2000
adb -s emulator-5554 shell wm density 360
adb -s emulator-5554 shell settings put system show_touches 1
adb -s emulator-5554 shell am start -n io.github.hashev.ffido/.MainActivity
```

Дождитесь загрузки каждого экрана перед следующим нажатием. Записывайте сценарии
по отдельности, перезапуская приложение для сброса демонстрационной сессии:

- `android-reading`: каталог → RU.FTN.DEVELOP → первое письмо → «Следующее» → список → каталог.
- `android-search`: список RU.FTN.DEVELOP → поиск `TLS` → «Найти далее» → следующий результат.
- `android-netmail-reply`: первое письмо → «Ответить лично» → адрес автора и цитата в черновике.

Запись экрана из отдельного терминала:

```sh
adb -s emulator-5554 shell screenrecord --size 900x2000 --bit-rate 4000000 /sdcard/demo.mp4
# Завершите запись Ctrl+C, затем скопируйте видео:
adb -s emulator-5554 pull /sdcard/demo.mp4 /tmp/demo.mp4
```

Преобразование из корня репозитория (замените имя выходного файла на нужный сценарий):

```sh
ffmpeg -i /tmp/demo.mp4 -filter_complex \
  '[0:v]fps=8,crop=900:1812:0:108,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=192:stats_mode=full[p];[b][p]paletteuse=dither=none:diff_mode=rectangle' \
  -loop 0 docs/images/android-reading.gif
```

Верхняя системная панель и нижняя полоска жестов обрезаны; интерфейс приложения
сохранён. В Git хранятся только GIF, исходные MP4 и промежуточные кадры остаются
в локальном `build/readme-recordings/`. Перед заменой файлов проверьте не только
первый кадр, но и все переходы, подсветку, черновик и отсутствие личных данных.
