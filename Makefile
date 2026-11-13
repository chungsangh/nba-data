.DEFAULT_GOAL := help
SHELL := /bin/bash

export NBA_DUCKDB_PATH ?= $(CURDIR)/data/nba.duckdb
export DBT_PROFILES_DIR := $(CURDIR)/transform
SEASONS ?=
DBT := cd transform && uv run dbt

.PHONY: help setup ingest deps build ci test lint fmt docs freshness clean metrics metrics-catalog metrics-check airflow-setup airflow-ui airflow-test airflow-run

help: ## Show available commands
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Install Python deps, dbt packages and git hooks
	uv sync
	$(DBT) deps
	uv run pre-commit install

ingest: ## Load data (SEASONS="2026 2027"; default: current season)
	uv run nba-ingest $(if $(SEASONS),--seasons $(SEASONS))

build: ## dbt build (models + unit tests + data tests)
	$(DBT) build

ci: ## Run the CI dbt checks locally (BASELINE_DIR=<main state> for Slim CI)
	scripts/ci_dbt.sh

test: ## Python tests and dbt unit tests only
	uv run pytest
	$(DBT) test --select "test_type:unit"

metrics: ## Query a metric, e.g. make metrics M=offensive_rating G=team__team_abbreviation
	cd transform && uv run mf query --metrics $(M) $(if $(G),--group-by $(G))

metrics-catalog: ## Regenerate METRICS.md from the semantic layer
	$(DBT) parse --quiet
	uv run python scripts/metrics_catalog.py

metrics-check: ## Validate the semantic layer and run known-answer metric tests
	cd transform && uv run mf validate-configs
	uv run python scripts/check_metrics.py

freshness: ## Check source freshness
	$(DBT) source freshness

lint: ## Run every pre-commit hook on the whole repo
	uv run pre-commit run --all-files

fmt: ## Auto-fix SQL and Python formatting
	uv run sqlfluff fix transform/models transform/tests
	uv run ruff format .

docs: ## Build and serve dbt docs on http://localhost:8080
	$(DBT) docs generate && $(DBT) docs serve

# ---- Airflow (separate environment in orchestration/) ----
AIRFLOW_ENV := AIRFLOW_HOME=$(CURDIR)/orchestration/.airflow AIRFLOW__CORE__LOAD_EXAMPLES=False \
	AIRFLOW__CORE__DAGS_FOLDER=$(CURDIR)/orchestration/dags
DAG ?= nba_daily

airflow-setup: ## Install Airflow + Cosmos and initialize Airflow's local metadata DB
	cd orchestration && uv sync && $(AIRFLOW_ENV) uv run airflow db migrate
	$(DBT) parse --quiet

airflow-ui: ## Airflow UI on http://localhost:8080 (login printed in the output)
	$(DBT) parse --quiet
	cd orchestration && $(AIRFLOW_ENV) uv run airflow standalone

airflow-test: ## DAG integrity tests
	$(DBT) parse --quiet
	cd orchestration && $(AIRFLOW_ENV) uv run pytest

airflow-run: ## Run a DAG once, headless, like the scheduled prod job (DAG=nba_daily)
	$(DBT) parse --quiet
	cd orchestration && $(AIRFLOW_ENV) uv run airflow dags test $(DAG)

clean: ## Remove dbt build output (keeps data)
	$(DBT) clean
