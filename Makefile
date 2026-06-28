POSTGRES_PORT ?= 55432

.PHONY: build up test down psql

build:
	docker compose build

up:
	POSTGRES_PORT=$(POSTGRES_PORT) docker compose up

test:
	POSTGRES_PORT=$(POSTGRES_PORT) docker compose run --rm pipeline_tester
	docker compose down -v

down:
	docker compose down -v

psql:
	docker compose exec postgres psql -U postgres -d lab
