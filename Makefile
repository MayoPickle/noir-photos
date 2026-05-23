.PHONY: api-test api-dev

api-test:
	cd services/api && python -m pytest

api-dev:
	cd services/api && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

