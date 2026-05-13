# Yandex Cloud DDNS

Docker-контейнер обновляет существующую A-запись `home.churneya.ru` в Yandex Cloud DNS текущим внешним IPv4-адресом сети, где запущен контейнер.

## Файлы

- `Dockerfile` - образ с `yc` CLI, `curl` и `jq`.
- `ddns-yandex.sh` - основной DDNS-цикл.
- `healthcheck.sh` - проверка свежести последней успешной проверки.
- `.env.example` - шаблон переменных окружения.
- `compose.yaml` - пример запуска.

## Настройка

Скопируй `.env.example` в `.env` и заполни значения:

```sh
cp .env.example .env
```

`YC_SERVICE_ACCOUNT_KEY_JSON` должен содержать authorized key JSON сервисного аккаунта Yandex Cloud. Сервисный аккаунт должен иметь права на чтение и изменение DNS-записи в нужной зоне.

Запись `DNS_RECORD_NAME` должна уже существовать. Контейнер не создает новые записи.

## Запуск

```sh
docker compose up -d
docker compose logs -f yandex-cloud-ddns
```

## Проверка

```sh
docker compose ps
dig +short home.churneya.ru
```

По умолчанию проверка выполняется раз в 15 минут:

```env
CHECK_INTERVAL_SECONDS=900
```

TTL обновляемой записи:

```env
DNS_RECORD_TTL=60
```
