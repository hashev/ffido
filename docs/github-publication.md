# Публикация FFIDO на GitHub

## Утверждённые решения и текущий статус

| Параметр | Значение |
| --- | --- |
| Репозиторий | https://github.com/hashev/ffido, личный аккаунт, public |
| Лицензия своего кода | MIT; лицензии зависимостей сохраняются отдельно |
| История | новая публичная история; старая `.git` не переносится |
| Основная ветка | master |
| Участие | только приглашённые Collaborators могут создавать PR |
| Слияние | PR + ci-required, 0 approvals, squash, без bypass |
| Application ID | io.github.hashev.ffido |
| Desktop signing | unsigned, macOS ad-hoc, без notarization |
| Android signing | постоянный keystore, требуется до публикации |
| Каналы | prerelease после merge; stable по vX.Y.Z |
| Публичный выпуск | FFIDO_PUBLICATION_READY=false до полной проверки |

Начальная `master` создана 19 октября 2026 года с MIT и коротким README
(коммит `137312c`); она назначена основной веткой. Исходники и workflow находятся
в [первом PR](https://github.com/hashev/ffido/pull/1), который проверяется GitHub CI.
Настройки доступа и защиты проверяются `audit_github.py`. Публикация пакетов
остаётся выключенной независимо от результатов CI; включение требует отдельного
решения владельца и настройки постоянного Android-ключа.

## 1. Подготовка локального каталога

Из корня исходного монорепозитория:

```sh
python3 -m unittest discover -s scripts/release -p 'test_*.py' -v
python3 scripts/release/export.py ../ffido-publication
```

Каталог назначения должен быть новым и находиться вне исходного дерева.
Экспортирует текущее состояние файлов, включая незакоммиченный монорепозиторий,
но не `.git`, рабочие конфиги/базы, ключи, кеши, uploads и временные checkout.
Исходный каталог сохраняется. Проверка секретов — дополнительная защита, а не
замена ручному review: проверьте `PUBLICATION-MANIFEST.json`, весь список файлов
и `machine_reference_review`. Исторические документы OpenSpec могут упоминать
прежние локальные пути; они не являются путями сборки. Не загружайте ненужные
персональные документы и не исправляйте исторические архивы без причины.

Повторите сборку/тесты из экспортированного каталога по README. Для новой истории
аудит старых коммитов не требуется: они не копируются. Проверьте, что в экспорте
нет `.git`, баз, реальных конфигов, ссылок на внешние файлы и закрытых ключей.
Не используйте `git add .` в исходном смешанном рабочем дереве.

MIT утверждена владельцем. Перед выпуском бинарников проверьте фактическое наличие
legal/source/relink материалов в каждом серверном пакете; MIT не снимает условия
LGPL/Library GPL для включённого Husky. Клиент содержит лицензии Flutter-плагинов.

## 2. Новая история и первоначальная master

Эти команды **публикуют файлы**. Выполняйте их только после review каталога и
отдельного разрешения владельца. Подготовка сценариев сама по себе их не запускает.

Нужна существующая master, чтобы открыть первый PR. Рекомендуемый bootstrap:
создать отдельный seed-каталог с утверждёнными LICENSE и коротким README, затем:

```sh
cd <seed-каталог>
git init -b master
git add LICENSE README.md
git commit -m 'Initialize FFIDO public repository'
git remote add origin https://github.com/hashev/ffido.git
git push -u origin master
gh api --method PATCH repos/hashev/ffido -f default_branch=master
```

GitHub ruleset допускает начальное создание ветки без status check
(`do_not_enforce_on_create`); это не разрешение последующих прямых обновлений.
Если GitHub отклонит именно bootstrap из-за обязательного PR, сначала проверить
точную причину через API; не добавлять постоянный bypass. Любое разовое изменение
правила требует отдельного решения владельца и немедленного восстановления.

После seed клонируйте новый репозиторий в ещё один каталог, создайте ветку
`codex/prepare-publication`, перенесите проверенный экспорт без `.git`, просмотрите
`git diff --cached`, закоммитьте и создайте PR в master. Старую историю не import,
не выполняйте `git push --mirror`. Первый PR оставьте открытым до проверки CI.

## 3. Проверка настроек доступа

В Settings → General → Features: Pull requests → **Collaborators only**.
В Settings → Collaborators приглашайте только выбранных участников.
Сейчас доступ к записи выдан только hashev; скачивание исходников/релизов публично.

Settings → Rules → Rulesets: активное правило master/default branch, без bypass:
Require PR, approvals=0, Require conversation resolution, Require status checks
`ci-required` от GitHub Actions с актуальной базой, Block force pushes,
Restrict deletions. Не включайте Restrict updates вместо PR: это может заблокировать
и нормальное слияние. Разрешён squash merge; обязательного второго reviewer нет.

Read-only проверка:

```sh
python3 scripts/release/audit_github.py
```

До bootstrap она закономерно сообщает, что default branch ещё main.
После первого запуска PR убедитесь в UI, что `ci-required` появился с точным именем.
Проверка с intentional failing check должна запретить merge; зелёная — позволить
владельцу слить собственный PR. Force/delete сценарии проверяйте в одноразовом
репозитории с тем же правилом, не разрушая рабочую master. Не делайте реальный
прямой push «для теста», если его успех добавит нерассмотренный код.

## 4. CI и зависимости

`ci.yml` вызывает `build.yml`. PR не получает signing secrets и write-токен.
Обязательные jobs: release-tools tests, клиентские analyze/test/build на пяти
OS/arch вариантах, backend build/CTest/HPT/static checks/proto на трёх вариантах.
Тестовый HPT собирается из закреплённых Husky-ревизий в локальном build-prefix.
`check_ctest.py` запрещает отсутствующий HPT и skipped tests. amster2 не используется.

Матрица использует Flutter 3.41.6, Java 17, Ubuntu 24.04, Windows 2022 runner,
macOS 15 arm64 и macos-15-intel. Actions закреплены полными commit SHA.
Кеш dependency prefix привязан к runner/архитектуре, fingerprint compiler/SDK/внешних библиотек и содержимому builder scripts.
При смене компилятора/образа сбросьте кеш; не переиспользуйте несовместимые объекты.

Actions → General: workflow permissions Read repository contents; PR approvals
автоматизации выключены. Allow selected actions: GitHub-owned и
`subosito/flutter-action@*` (в YAML всё равно pinned SHA). Другие actions сначала
добавляйте в явный allowlist и проходите review.

## 5. Постоянный Android signing key

Создание ключа выполняет владелец локально в каталоге **вне Git**. Пример:

```sh
keytool -genkeypair -v -keystore ffido-release.jks -alias ffido \
  -keyalg RSA -keysize 4096 -validity 10000
keytool -list -v -keystore ffido-release.jks -alias ffido
```

Сохраните файл, alias и пароли в защищённой резервной копии. Не отправляйте пароли
в чат, не включайте shell tracing. Без этого же ключа обновления Android могут
потребовать переустановки. Публичный application ID уже выбран; старый com.example
считается отдельным приложением, профили не копируются автоматически.

Settings → Environments → **release**: разрешить deployment master и контролируемых
тегов `v*`, без обязательного reviewer (иначе выпуск перестанет быть автоматическим).
Environment release и политики master/v* уже созданы через gh; секреты ещё не добавлены.
Создайте environment secrets:

- `ANDROID_KEYSTORE_BASE64`: Base64 содержимого keystore без дополнительных строк;
- `ANDROID_KEYSTORE_PASSWORD`;
- `ANDROID_KEY_ALIAS`;
- `ANDROID_KEY_PASSWORD`.

Создайте environment variable `ANDROID_CERT_SHA256` — fingerprint из keytool.
Workflow сверяет сертификат готового APK и отклоняет debug-подпись. Временный
keystore создаётся только в signing job, с правами 600 и удалением при завершении.

Desktop на первом этапе без Apple Developer ID/Authenticode. `codesign -s -`
на macOS — ad-hoc, а не подтверждение издателя или notarization. Переход к подписанным
desktop-пакетам требует отдельного изменения pipeline и секретов; текущий упаковщик
не выдаёт неподписанный пакет за подписанный.

## 6. Первый prerelease

Пока проверка пакетов, подпись и legal-комплект не готовы, оставьте repository
variable `FFIDO_PUBLICATION_READY=false`. Release workflow всё ещё проверяет и
собирает неподписанные CI-пакеты, но signing/publish jobs не выполняются.
Публичных пакетов из debug APK не будет.

После успешной проверки полного набора, ключа и лицензий:

```sh
gh variable set FFIDO_PUBLICATION_READY --repo hashev/ffido --body true
```

Следующий merge PR в master запускает Release на итоговом SHA. Для первого
проверенного master можно вручную запустить Release → Run workflow → master.
Ручной retry допускает только доверенный SHA master, не произвольную feature branch.

Версия берётся из `apps/frontend/pubspec.yaml`. Build number — release workflow
run number + offset 1000. Prerelease: `vX.Y.Z-dev.N.<sha>`. При переименовании/замене
workflow нельзя обнулить Android versionCode: увеличьте offset через PR.

Публикация собирает восемь целевых пакетов одного запуска, сверяет manifest и
SHA-256, создаёт draft, загружает файлы, повторно скачивает и проверяет их и только
после этого открывает релиз. Уже публичные файлы не заменяются молча.
Пакеты должны скачиваться без авторизации со страницы Releases, а не только
из временных Actions artifacts.

## 7. Stable и сопровождение

Измените base version через обычный PR. Дождитесь успешного CI/merge, затем:

```sh
git fetch origin master
git tag -a vX.Y.Z <проверенный-SHA-master> -m 'FFIDO X.Y.Z'
git push origin vX.Y.Z
```

Тег должен совпадать с версией исходников и указывать на коммит истории master.
Два активных tag ruleset уже настроены: создание stable-тегов только владельцем,
запрет обновления и удаления всех тегов v*. Правило создания исключает v*-dev.*,
чтобы GITHUB_TOKEN мог создавать автоматические prerelease-теги без отдельного PAT. Не применяйте к стабильным тегам
постоянный bypass всех правил. Пример процесса: отдельное правило создания с
правом владельца и отдельное правило запрета удаления/force без bypass.

Stable пересобирается и проверяется тем же набором jobs, получает полный SHA,
BUILD metadata, manifest и контрольные суммы. Он не является просто переименованием
непроверенного CI-архива.

При инфраструктурном сбое повторите тот же run: draft можно дозагрузить, публичную
версию менять нельзя. При дефекте кода исправьте обычным PR и выпустите новую
версию. Workflow concurrency изолирует повтор одного run; разные merged SHA получают
собственные версии и не ставятся в глобальную concurrency-группу, которая могла бы
отменить ожидающий выпуск. Артефакты берутся только из текущего run.

Перед обновлением backend нужна согласованная backup по README. Ошибочный релиз
пометьте в release notes и предложите предыдущий пакет; не откатывайте схему SQLite
поверх изменённых данных вслепую.

## Критерий завершения первой публикации

Локально: manifest/secret scan, тесты release-tools, YAML/actionlint, чистые
build/test и smoke доступных пакетов. Удалённо: зелёный полный CI, реальные правила
PR/master, постоянная подпись APK и anonymous download полного prerelease/stable.
Недоступная проверка не считается пройденной и отмечается в docs/testing.md.
Commit/push и публикация выполняются только по отдельному запросу владельца.
