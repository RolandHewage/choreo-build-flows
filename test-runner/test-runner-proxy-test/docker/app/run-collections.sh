#!/bin/sh

# Simplified run-collections.sh for E2E test
# Production version parses --files flag and runs newman per collection

for file in /etc/postman/*.json; do
  newman run "$file"
done
