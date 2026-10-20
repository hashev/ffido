# Обновление Flutter и зависимостей — 20 октября 2026

Исходный SDK: Flutter 3.41.6 / Dart 3.11.4. Целевой stable: Flutter 3.47.7 / Dart 3.13.5. Framework revision: `abaf9c523780a608bd46686fd5e53740a07077f8`.

Источник: [официальный manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json), `current_release.stable`; дата проверки 2026-10-20. Общий SDK разработчика не изменяется; проверочная установка — отдельная.

## Исходный отчёт outdated

| Проект | Пакет | Current | Resolvable | Latest |
|---|---|---|---|---|
| frontend | _fe_analyzer_shared | 93.0.0 | 93.0.0 | 109.0.0 |
| frontend | analyzer | 10.0.1 | 10.0.1 | 14.5.0 |
| frontend | build | 4.0.5 | 4.0.7 | 5.0.0 |
| frontend | build_config | 1.3.0 | 1.3.3 | 1.4.0 |
| frontend | build_daemon | 4.1.1 | 4.1.7 | 4.1.7 |
| frontend | build_runner | 2.13.1 | 2.15.1 | 2.17.1 |
| frontend | built_collection | 5.1.1 | 5.1.2 | 5.1.2 |
| frontend | built_value | 8.12.5 | 8.13.0 | 8.13.0 |
| frontend | clock | 1.1.2 | 1.1.2 | 1.1.3 |
| frontend | code_assets | 1.2.1 | 1.2.1 | 2.1.0 |
| frontend | code_builder | 4.11.1 | 4.13.0 | 4.13.0 |
| frontend | cross_file | 0.3.5+5 | 0.3.5+5 | 0.4.0 |
| frontend | cupertino_icons | 1.0.9 | 1.0.9 | 2.0.0 |
| frontend | dart_style | 3.1.7 | 3.1.7 | 3.1.14 |
| frontend | file_selector_android | 0.5.2+6 | 0.5.2+6 | 0.5.2+11 |
| frontend | file_selector_ios | 0.5.3+6 | 0.5.3+6 | 0.5.3+7 |
| frontend | file_selector_macos | 0.9.5+1 | 0.9.5+1 | 0.9.5+2 |
| frontend | flutter_lints | 5.0.0 | 6.0.0 | 6.0.0 |
| frontend | glob | 2.1.3 | 2.2.0 | 2.2.0 |
| frontend | grpc | 5.1.0 | 5.2.0 | 5.2.0 |
| frontend | hooks | 2.0.2 | 2.0.2 | 2.2.0 |
| frontend | http2 | 2.3.1 | 2.3.1 | 3.1.0 |
| frontend | io | 1.0.5 | 1.1.0 | 1.1.0 |
| frontend | json_annotation | 4.11.0 | 4.12.0 | 4.12.0 |
| frontend | lints | 5.1.1 | 6.1.0 | 6.1.0 |
| frontend | matcher | 0.12.19 | 0.12.19 | 0.12.20 |
| frontend | material_color_utilities | 0.13.0 | 0.13.0 | 0.13.1 |
| frontend | meta | 1.17.0 | 1.17.0 | 1.19.0 |
| frontend | mime | 2.0.0 | 2.1.0 | 2.1.0 |
| frontend | mockito | 5.6.4 | 5.6.4 | 5.8.1 |
| frontend | objective_c | 9.5.0 | 9.5.0 | 9.6.2 |
| frontend | package_config | 2.2.0 | 2.2.0 | 3.0.0 |
| frontend | path_provider_linux | 2.2.1 | 2.2.2 | 2.2.2 |
| frontend | path_provider_platform_interface | 2.1.2 | 2.1.3 | 2.1.3 |
| frontend | platform | 3.1.6 | 3.1.6 | 3.2.0 |
| frontend | pool | 1.5.2 | 1.5.3 | 1.5.3 |
| frontend | pub_semver | 2.2.0 | 2.2.1 | 2.2.1 |
| frontend | pubspec_parse | 1.5.0 | 1.6.0 | 1.6.0 |
| frontend | record_use | 0.6.0 | 0.6.0 | 1.1.1 |
| frontend | shared_preferences | 2.5.5 | 2.5.6 | 2.5.6 |
| frontend | shared_preferences_android | 2.4.23 | 2.4.23 | 2.5.1 |
| frontend | shared_preferences_foundation | 2.5.6 | 2.5.7 | 2.6.0 |
| frontend | shelf | 1.4.2 | 1.4.3 | 1.4.3 |
| frontend | source_gen | 4.2.2 | 4.2.4 | 4.3.1 |
| frontend | stack_trace | 1.12.1 | 1.12.1 | 1.12.2 |
| frontend | stream_transform | 2.1.1 | 2.1.2 | 2.1.2 |
| frontend | test_api | 0.7.10 | 0.7.10 | 0.7.15 |
| frontend | vector_math | 2.2.0 | 2.2.0 | 2.4.3 |
| frontend | vm_service | 15.0.2 | 15.4.0 | 15.4.0 |
| frontend | yaml | 3.1.3 | 3.1.4 | 3.1.4 |
| proto | dart_style | 3.1.13 | 3.1.14 | 3.1.14 |

## Результат обновления

47 зависимостей клиента обновлены. Для `tools/proto` обновлён dart_style 3.1.13 → 3.1.14; protoc_plugin 25.1.0 и protoc 36.2 остались актуальным совместимым набором. SDK constraints обоих пакетов: Dart >=3.13.0 <4.0.0. Минимальные ОС не повышались.

| Пакет клиента | Было | Стало |
|---|---|---|
| _fe_analyzer_shared | 93.0.0 | 109.0.0 |
| analyzer | 10.0.1 | 14.5.0 |
| build | 4.0.5 | 4.0.11 |
| build_config | 1.3.0 | 1.3.3 |
| build_daemon | 4.1.1 | 4.1.7 |
| build_runner | 2.13.1 | 2.16.2 |
| built_collection | 5.1.1 | 5.1.2 |
| built_value | 8.12.5 | 8.13.0 |
| clock | 1.1.2 | 1.1.3 |
| code_assets | 1.2.1 | 2.1.0 |
| code_builder | 4.11.1 | 4.13.0 |
| cupertino_icons | 1.0.9 | 2.0.0 |
| dart_style | 3.1.7 | 3.1.14 |
| file_selector_android | 0.5.2+6 | 0.5.2+11 |
| file_selector_ios | 0.5.3+6 | 0.5.3+7 |
| file_selector_macos | 0.9.5+1 | 0.9.5+2 |
| flutter_lints | 5.0.0 | 6.0.0 |
| glob | 2.1.3 | 2.2.0 |
| grpc | 5.1.0 | 5.2.0 |
| hooks | 2.0.2 | 2.2.0 |
| io | 1.0.5 | 1.1.0 |
| json_annotation | 4.11.0 | 4.12.0 |
| lints | 5.1.1 | 6.1.0 |
| matcher | 0.12.19 | 0.12.20 |
| meta | 1.17.0 | 1.19.0 |
| mime | 2.0.0 | 2.1.0 |
| mockito | 5.6.4 | 5.8.1 |
| objective_c | 9.5.0 | 9.6.2 |
| package_config | 2.2.0 | 3.0.0 |
| path_provider_linux | 2.2.1 | 2.2.2 |
| path_provider_platform_interface | 2.1.2 | 2.1.3 |
| platform | 3.1.6 | 3.2.0 |
| pool | 1.5.2 | 1.5.3 |
| pub_semver | 2.2.0 | 2.2.1 |
| pubspec_parse | 1.5.0 | 1.6.0 |
| record_use | 0.6.0 | 1.1.1 |
| shared_preferences | 2.5.5 | 2.5.6 |
| shared_preferences_android | 2.4.23 | 2.5.1 |
| shared_preferences_foundation | 2.5.6 | 2.6.0 |
| shelf | 1.4.2 | 1.4.3 |
| source_gen | 4.2.2 | 4.3.1 |
| stack_trace | 1.12.1 | 1.12.2 |
| stream_transform | 2.1.1 | 2.1.2 |
| test_api | 0.7.10 | 0.7.12 |
| vector_math | 2.2.0 | 2.4.3 |
| vm_service | 15.0.2 | 15.4.0 |
| yaml | 3.1.3 | 3.1.4 |

### Оставшиеся ограничения

| Пакет | Установлено | Latest | Цепочка ограничения |
|---|---|---|---|
| build | 4.0.11 | 5.0.0 | mockito 5.8.1 → build >=3.0.0 <5.0.0 |
| build_config | 1.3.3 | 1.4.0 | mockito → build <5 → build_runner 2.16.2 → build_config >=1.3.2 <1.4.0 |
| build_runner | 2.16.2 | 2.17.1 | mockito 5.8.1 требует build <5; build_runner 2.17.1 требует build >=5.0.0 <5.1.0 |
| cross_file | 0.3.5+5 | 0.4.0 | file_selector 1.1.0 → file_selector_platform_interface 2.7.0 → cross_file ^0.3.0 |
| http2 | 2.3.1 | 3.1.0 | grpc 5.2.0 → http2 ^2.3.1 |
| material_color_utilities | 0.13.0 | 0.13.1 | Flutter 3.47.7 → material_color_utilities: 0.13.0 |
| test_api | 0.7.12 | 0.7.15 | Flutter 3.47.7 / flutter_test → test_api: 0.7.12 |

Проверено по pubspec установленных пакетов и [pub.dev API](https://pub.dev/api/packages/build_runner/versions/2.17.1). У tools/proto нет устаревших зависимостей. Overrides не добавлены. Прямые зависимости не удерживаются прежними ограничениями проекта. Сообщение о 7 пакетах ожидаемо для последнего совместимого набора.

## Проверки

- Flutter analyze: без замечаний; Flutter test: 230 passed, 2 существующих пропуска.
- enforce-lockfile для обоих пакетов: успешно; protoc generation --check: успешно, wire-контракт не изменён.
- Dart format: 86 файлов, 0 изменений при повторной проверке. Новый formatter Dart 3.13 изменил оформление 59 файлов; исправлены два prefer_initializing_formals без изменения API конструктора.
- Корневая Debug CMake-сборка и CTest: 350/350, включая HPT, без пропусков. C++ format/clang-tidy: 99 файлов / 51 translation units, успешно.
- Release-tools: 26 тестов успешно; actionlint и OpenSpec strict validation успешны; экспорт исходников: 0 найденных секретов.
- Локальные release-сборки и запуск macOS, Android API 36 arm64 и Linux amd64 успешны. Пакеты macOS/Linux извлечены и проверены существующими package.py/smoke.py; Android APK проверен на устройстве-эмуляторе без изменения пользовательских AVD. Нативные тесты профилей macOS прошли.
- Прямой TLS gRPC acceptance нового Dart-клиента против backend прошёл: сертификат/ALPN, отказ без авторизации, Unicode, ответы, идемпотентность, UUE и метаданные.
- Полная клиентская и серверная матрица прошла в [PR #6 / run 39453112427](https://github.com/hashev/ffido/actions/runs/39453112427), затем повторно в доверенном Release: macOS arm64/x86_64, Windows/Linux x86_64, Android; серверы Linux x86_64 и macOS arm64/x86_64. Упаковка и smoke выполнены.

## Платформенные миграции

- Android: Gradle 8.12 → 9.3.1, AGP 8.9.1 → 9.1.0, Kotlin plugin 2.1.0 → 2.4.0, Java/Kotlin target 17. Версии взяты из шаблона установленного Flutter 3.47.7 (`gradle_utils.dart`); прежний Gradle ниже обязательного минимума 8.14, AGP ниже 8.11.1 и Kotlin ниже 2.2.20. Идентификатор приложения, minSdk 24 и release signing сохранены. Встроенный Kotlin включён (`android.builtInKotlin=true`), отдельный kotlin-android plugin удалён. Флаг `android.newDsl=false` нужен из-за обращения Gradle-плагина Flutter к legacy AGP DSL; newDsl=true подтверждённо вызывает ClassCastException. Он не обходит dependency validation.
- macOS: общий Architecture.xcconfig отображает native arm64e Xcode 27 в поддерживаемый Flutter arm64, сохраняя отдельную сборку x86_64 на Intel. Сборка arm64 и запуск извлечённого DMG прошли. Xcode выводит рекомендацию по arm64-only; существующая матрица Intel сохраняется. Flutter автоматически подключил SwiftPM для плагинов и обновил Xcode project/scheme и Podfile.lock. Полное удаление оставшейся CocoaPods-интеграции нестандартного Podfile не требуется для успешной сборки и не выполнялось попутно.

## Docker и фактическая публикация

Docker Linux amd64 собран; CTest внутри builder прошёл 350/350 без пропусков от непривилегированного пользователя. Runtime 10001:10001 содержит admin/helper/wrapper, библиотеки, лицензионные архивы и материалы перелинковки. Фактический BuildKit context отдельно проверен на отсутствие локальных конфигов, ключей, FTN/SQLite и сборочных кешей.

Container smoke проверил TLS, ошибки конфигурации и прав, SIGTERM и пересоздание с сохранением действительной сессии, сообщения, read state, закладки и незавершённой загрузки. Признак прочтения проверяется до открытия сообщения; текст сравнивается точно до и после остановки с учётом нормализации JAM. Перенос через локальный registry сохранил digest; идемпотентность публикации проверена настоящими inspect/copy.

Права pull,push проверены [отдельным workflow без загрузки образа](https://github.com/hashev/ffido/actions/runs/39460929276). Затем [автоматический Release 39460898488](https://github.com/hashev/ffido/actions/runs/39460898488), запущенный push после слияния PR #6, успешно опубликовал образ:

- GitHub Release: [v1.0.0-dev.1003.9e8e79c94706](https://github.com/hashev/ffido/releases/tag/v1.0.0-dev.1003.9e8e79c94706).
- Source SHA: `9e8e79c94706687d3f415e35046bd96cad373ff6`.
- Docker image: `docker.io/hashev/ffido:1.0.0-dev.1003.9e8e79c94706`.
- Digest: `sha256:eb800cd08c10fafb67784e87ba1aa8ce0c690ac62f79e9c67058a4826163567d`.

SHA/версия/digest совпали с release-manifest.json и его SHA256SUMS. Версия и SHA-тег указывают на один digest. Тег latest отсутствовал до prerelease и после него остался отсутствующим. Выполнены независимый анонимный pull по опубликованному digest и полный container smoke локально; GitHub Actions также повторил smoke после pull из Docker Hub. Секреты не потребовались для скачивания образа и не выводились в логи.

```sh
docker pull --platform linux/amd64 docker.io/hashev/ffido@sha256:eb800cd08c10fafb67784e87ba1aa8ce0c690ac62f79e9c67058a4826163567d
```

В CI сохраняются предупреждения GitHub о Node.js 20 у ранее закреплённых actions; runner запускает их на Node.js 24. Обновление этих существующих action pins не входило в обновление Flutter и добавление Docker-публикации.

Для BuildKit gha cache используется API v2 и scope ffido-server-amd64. Inline buildx требует экспорта ACTIONS_RESULTS_URL/ACTIONS_RUNTIME_TOKEN из JavaScript action; значения маскируются и передаются только exporter, без build args и записи в образ. Источник: [Docker cache authentication](https://docs.docker.com/build/cache/backends/gha/). Сохранение и тёплый повтор проверяются в CI.
