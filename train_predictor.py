#!/usr/bin/env python3
import warnings
from sklearn.exceptions import ConvergenceWarning
warnings.filterwarnings("ignore", category=ConvergenceWarning)
import pandas as pd
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
import pickle
import os

csv_path = '/root/Valtracker/commands.csv'
model_path = '/root/Valtracker/cmd_model.pkl'
if not os.path.isfile(csv_path):
    print(f"{csv_path} does not exist, nothing to train.")
    exit(0)

df = pd.read_csv(csv_path, sep='|', names=['command', 'timespan', 'result'])
df = df[~df['result'].isin(['NA'])]
if df.empty or df['command'].dropna().empty:
    print("No command data found, skipping ML training.")
    exit(0)
if len(df['command'].dropna()) < 1:
    print("Insufficient data to train ML model.")
    exit(0)
df = df.dropna()
df['result'] = (df['result'] == 'PASS').astype(int)
vectorizer = CountVectorizer()
X_cmd = vectorizer.fit_transform(df['command'])
X = pd.DataFrame(X_cmd.toarray())
X['timespan'] = df['timespan'].astype(float).reset_index(drop=True)
X.columns = X.columns.astype(str)
y = df['result'].reset_index(drop=True)
if len(set(y)) < 2:
    print("Insufficient data: only one class present in results (all PASS or all FAIL). Model not trained.")
    exit(0)

model = LogisticRegression(max_iter=2000)
model.fit(X, y)
with open(model_path, 'wb') as f:
    pickle.dump((model, vectorizer), f)
print("ML training completed.")
