#!/usr/bin/env python3
import sys
import pickle
import pandas as pd

# Print help if not enough arguments
if len(sys.argv) < 2:
    print("Usage: predict_cmd.py '<command_for_prediction>' [timespan]")
    print("  <command_for_prediction>: The shell command string whose PASS/FAIL probability you want to predict.")
    print("  [timespan]: (optional) Estimated timespan (float, in seconds); defaults to 1.0")
    sys.exit(1)

cmd = sys.argv[1]
timespan = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0

try:
    with open('/root/Valtracker/cmd_model.pkl', 'rb') as f:
        model, vectorizer = pickle.load(f)
except Exception as e:
    print(f"Could not load ML model: {e}")
    sys.exit(2)

try:
    X_cmd = vectorizer.transform([cmd])
    X = pd.DataFrame(X_cmd.toarray())
    X['timespan'] = timespan
    X.columns = X.columns.astype(str)
    prob = model.predict_proba(X)[0][1]
    print(f"Predicted PASS probability: {prob:.2f}")
except Exception as e:
    print(f"Error in prediction: {e}")
    sys.exit(3)
