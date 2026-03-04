"""Simple app that imports pip-installed dependency to confirm the build worked."""
import requests

print("Python pip proxy E2E test — build succeeded!")
print(f"  requests version: {requests.__version__}")
