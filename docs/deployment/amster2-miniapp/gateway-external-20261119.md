# Публичный9443: firewall и внешняя проверка

19.11.2026 по отдельному разрешению открыт IPv4 TCP9443 на amster2.
Backend/tosser, native8080, тестовые8443/backend и остальные службы не перезапускались.
Основной backend в каталог НЕ опубликован; Web-сборка не публиковалась.

## Применённое правило и сохранение

Активный filter/AMSTER-INPUT: добавлено ровно одно правило перед terminal ens3 DROP:

```text
-A AMSTER-INPUT -i ens3 -p tcp -m tcp --dport 9443 -j ACCEPT
```

Gateway использует host network, поэтому AMSTER-DOCKER/DOCKER-USER/DNAT не менялись.
IPv6 AMSTER-INPUT не изменён: listener9443 и DNS endpoint используются по IPv4.

На сервере нет `/etc/iptables/rules.v4`. Постоянный источник —
`/usr/local/sbin/amster-firewall`, запускаемый enabled
`/etc/systemd/system/amster-firewall.service`. В существующий script добавлен
IPv4-only emit ACCEPT9443 перед DROP; прочие порты/ветви сохранены.
Точечная установка live правила без полного reload/flush и без рестарта Docker.

Проверки сохранения: `sh -n` успешен, service enabled, безопасное исполнение script
с подменёнными iptables/restore в отдельном PATH подтвердило генерацию ровно одного
ACCEPT9443 перед DROP только в IPv4. Kernel правила этим render-тестом не менялись;
перезагрузка сервера не выполнялась.

Исходные script, iptables-save/ip6tables-save, итоговый script, systemd unit и private
свидетельства сохранены в `/srv/ffido-miniapp-main/firewall9443-20261119` (0700).
`change.json` подтверждает неизменность остальных IPv4 rules, IPv6, Docker policy,
image/start times всех семи рабочих и тестовых контейнеров.
В будущий полный backup persistent firewall включать именно этот script И unit,
а не рассчитывать на отсутствующий `/etc/iptables/rules.v4`.

Откат только допуска9443: удалить точное правило из AMSTER-INPUT и вернуть
`amster-firewall.before` с режимом0750 на исходный путь под maintenance lock.
Не восстанавливать весь iptables-save поверх живых Docker/Tailscale chains.

## Почему обычная проверка с Mac была недостаточна

Обычный маршрут с Mac к146.103.99.3 проходил через utun7 и давал HTTP403 даже до
открытия внешнего порта. Это не доказывало проходимость ens3 ingress.

Проверка привязана к физическому **en0**:

- До изменения `curl --interface en0 --noproxy '*'` завершался TCP timeout.
- После — доверенный HTTPS ответ403 без Origin, ssl_verify_result=0.
- Полные RPC/Origin тесты выполнены Python socket с IP_BOUND_IF=25, проверенным
  по локальному Apple SDK, через en0 и публичный адрес146.103.99.3, с реальным SNI/Host.
- На сервере счётчик нового ens3 ACCEPT9443 вырос с0 до9 соединений/SYN packets.
  Глобальные маршруты/VPN/настройки сети Mac не менялись.

## Внешние результаты

URL: `https://f120n5015z2.ddns.net:9443`, Origin`https://hashev.github.io`.

- HTTPS TLS1.3: системная CA/hostname verification включена без -k;
  leaf DER точно совпал с отдельным production сертификатом gateway.
- CORS OPTIONS: точный ACAO, POST/OPTIONS и нужные authorization/content-type/
  x-grpc-web разрешены; grpc-status доступен через Expose-Headers.
- Чужой Origin и отсутствие Origin: HTTP403 без ACAO.
- GetServerCapabilities binary gRPC-Web: HTTP200, grpc-status0,
  supports_telegram=true; frames/protobuf/trailers декодированы.
- Text gRPC-Web с подходящим Accept: base64 frames, тот же protobuf и grpc-status0.
- ListConferences без сессии и ListTelegramProfiles без proof: grpc-status16,
  включая допустимый trailers-only ответ через initial headers.
- Пароли/токены не использовались, сообщения не читались и не отправлялись;
  реальный Telegram initData и вход пользователя в этом этапе не проверялись.

Серверный `external-validation.json` и локальные build/amster2-gateway-external-20261119
содержат результат. Все рабочие и тестовые контейнеры running, backend/tosser healthy;
image IDs/start times совпали с исходными. `git diff --check` успешен.

## Каталог

Read-only запрос опубликованного `https://hashev.github.io/ffido/backends.json`
после проверки вернул schema1 и только amster2-miniapp-test на8443.
Записи amster2-main/endpoint9443 нет. Никакой публикации не выполнялось.
Следующий самостоятельный этап — добавить основной backend в проверенный каталог
и провести настоящий браузерный/Telegram вход, только по отдельному разрешению.
