import os
import sys
from pathlib import Path

# Lets tests import the question sets (chat_eval_set.py, ...) next to them.
sys.path.insert(0, str(Path(__file__).parent))

# The tests call the API with the test token; the server itself refuses it unless asked (bug list #17).
os.environ["DEV_AUTH_BYPASS"] = "true"
