# Перелинковка серверного пакета

Собственный код FFIDO распространяется под MIT. Эта инструкция не ограничивает
права на модификацию сторонних библиотек: их лицензии находятся в legal/.

В серверном пакете:

- `share/ffido/ffido-source.tar.gz` — исходники FFIDO и адаптер открытия конфигов;
- `share/ffido/legal/*-<SHA>.tar.gz` — исходники Husky, gRPC, Protobuf, Abseil и
  grpc-proto с точными ревизиями в revisions.json;
- там же исходники spdlog, nlohmann/json и SQLite и лицензии внешних runtime libs;
- `share/ffido/relink/` — объектные файлы/архивы/библиотеки из команд линковки
  установленного сервера, admin и helper, с уникальными префиксами имён;
- `relink.sh` — команды перелинковки без исходного рабочего каталога разработчика.

Используйте совместимый C++23 compiler, SDK и архитектуру из BUILD.json.
Для Linux также нужен patchelf; macOS использует штатные install_name_tool/codesign.
`CXX=/путь/к/c++ sh relink.sh` создаёт новые бинарники в relink/bin.
Относительные runtime paths рассчитаны на сохранение структуры пакета.

Для изменения Husky распакуйте исходники huskylib, smapi, fidoconf из legal/ в
новый рабочий каталог и создайте свой отдельный prefix. Не перезаписывайте
установленный тоссер. Upstream CMake получает дату через git log; у tar-архива
нет .git. В каждом распакованном каталоге можно создать локальную метаинформацию:

```sh
git init
git add .
git -c user.name=Builder -c user.email=builder@localhost commit -m 'Source snapshot'
```

Это локальная метаинформация для версии, а не обращение к GitHub.
Собирайте по порядку huskylib → smapi → fidoconf, выполняя CMake из каталога
исходников компонента (upstream git log зависит от текущей папки):

```sh
cmake -S . -B build -DBUILD_SHARED_LIBS=OFF -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_PREFIX="$prefix" \
  -DCMAKE_C_FLAGS="-I$prefix/include" \
  -Dhusky_LIB="$prefix/lib/libhusky.a" -Dsmapi_LIB="$prefix/lib/libsmapi.a" \
  -DMAKEINFO=MAKEINFO-NOTFOUND
cmake --build build
cmake --install build
```

После модификации и сборки библиотеки замените соответствующий файл
`<уникальный-префикс>-libfidoconfig.a` (либо libhusky.a) в relink/ и выполните
relink.sh. При модификации cfg.c учтите, что helper использует отдельный объект
cfg.c.o с callback открытия: его исходник получается из fidoconf/src/cfg.c и
`cmake/patches/fidoconfig-open.patch` исходников FFIDO. Пересоберите и замените
этот объект также; иначе встроенный объект будет иметь приоритет над архивом.
Исходная SHA-проверка автоматического адаптера относится к штатной сборке FFIDO,
а не запрещает самостоятельную замену перед перелинковкой.

Не применяйте перепакованные/изменённые библиотеки сразу к рабочей JAM: сначала
проверьте на синтетической базе. Имя, подпись и контрольные суммы изменённого
пакета больше не соответствуют исходному официальному выпуску.
