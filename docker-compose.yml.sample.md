

``` yml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: lab_postgres
    environment:
      POSTGRES_DB: lab
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d lab"]
      interval: 3s
      timeout: 3s
      retries: 5

  flyway:
    image: flyway/flyway:10
    container_name: lab_migrations
    command: -url=jdbc:postgresql://postgres:5432/lab -user=postgres -password=postgres -locations=filesystem:/flyway/sql migrate
    volumes:
      - ./migrations:/flyway/sql
    depends_on:
      postgres:
        condition: service_healthy

  pipeline_tester:
    image: postgres:16-alpine
    container_name: lab_pipeline_tester
    volumes:
      - .:/app
    working_dir: /app
    environment:
      - DB_URL=postgresql://postgres:postgres@postgres:5432/lab
    command: ["/bin/bash", "./run_pipeline.sh"]
    depends_on:
      flyway:
        condition: service_completed_successfully
```