#!/usr/bin/env bash

rm -rf .venv
python3 -m venv .venv
source .venv/bin/activate
pip install -r pip-requirements.txt -r dev-requirements.txt -r production-requirements.txt
