#!/bin/sh
set -e

python scripts/reset_admin.py
python scripts/seed_biostat_knowledge.py

exec uvicorn app.main:app --host 0.0.0.0 --port 8000
