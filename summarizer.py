#!/usr/bin/env python3

import sys

from transformers import pipeline

LOG_FILE = sys.argv[1]
try:
    with open(LOG_FILE, 'r', encoding='utf-8', errors='replace') as f:
        logtext = f.read()
except Exception as e:
    print(f"Could not read log: {e}")
    sys.exit(1)

# Use a smaller, fast local model for summaries
try:
    summarizer = pipeline('summarization', model='sshleifer/distilbart-cnn-6-6')
except Exception as e:
    print("Could not load summarizer, install transformers/torch and make sure the model is accessible.")
    print(e)
    sys.exit(1)

# HuggingFace models have a max token length: summary chunking
max_input_len = summarizer.tokenizer.model_max_length if hasattr(summarizer, 'tokenizer') else 1024
if len(logtext) > 4000:
    logtext = logtext[-4000:] # Summarize only the last 4000 chars of massive logs

try:
    summary_obj = summarizer(logtext, max_length=100, min_length=25, do_sample=False)
    print("Log Summary:")
    print(summary_obj[0]['summary_text'])
except Exception as e:
    print("Could not summarize log:", e)
    print("Showing raw tail of log instead:")
    print(logtext[-500:])
