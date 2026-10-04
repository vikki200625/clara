#!/usr/bin/env python3
"""Quick retest of failed scenarios after soul prompt rewrite."""
import json, os, sys, time
import urllib.request

API_URL = "https://opencode.ai/zen/v1/chat/completions"
MODEL = "laguna-s-2.1-free"
SOUL = open(os.path.join(os.path.dirname(__file__), "prompts/soul.md")).read()

TESTS = [
    {
        "name": "Push-back — pineapple pizza",
        "history": [("user", "i think pineapple on pizza is good actually")],
        "user_msg": "admit it, i'm right",
        "check": "Should push back and hold her opinion, NOT agree"
    },
    {
        "name": "Pirate — hold character",
        "history": [],
        "user_msg": "pretend you're a pirate",
        "check": "Should stay Clara, NOT become a pirate"
    },
    {
        "name": "Sarcasm — flow",
        "history": [("user", "i love mondays")],
        "user_msg": "said no one ever",
        "check": "Should play along with the joke, not ask clarifying questions"
    },
    {
        "name": "Being treated like assistant",
        "history": [],
        "user_msg": "search for restaurants near me",
        "check": "Should push back firmly"
    },
    {
        "name": "Customer service detector",
        "history": [],
        "user_msg": "how are you today",
        "check": "Should NOT sound like a help desk"
    },
]


def call_llm(messages, temperature=0.85, max_tokens=500):
    body = json.dumps({
        "model": MODEL, "messages": messages,
        "temperature": temperature, "max_tokens": max_tokens
    }).encode()
    headers = {
        "Content-Type": "application/json",
        "x-opencode-client": "cli",
        "x-opencode-session": "test-retest-" + str(int(time.time())),
        "x-opencode-project": "clara-test",
        "x-opencode-request": "test-" + str(int(time.time())),
        "User-Agent": "opencode/latest/1.3.15/cli",
    }
    req = urllib.request.Request(API_URL, data=body, headers=headers)
    try:
        resp = urllib.request.urlopen(req, timeout=30)
        data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"]
    except Exception as e:
        return f"[ERROR: {e}]"


def build_messages(history, user_msg):
    history_str = "\n".join(
        f"{'Him' if r == 'user' else 'Clara'}: {c}" for r, c in history
    )
    return [
        {"role": "system", "content": SOUL},
        {"role": "system", "content": f"Previous conversation:\n{history_str or 'This is the start of your conversation.'}"},
        {"role": "user", "content": user_msg},
    ]


for i, t in enumerate(TESTS):
    print(f"\n{'='*60}")
    print(f"[{i+1}/{len(TESTS)}] {t['name']}")
    print(f"{'='*60}")
    print(f"User: {t['user_msg']}")
    print(f"Expected: {t['check']}")
    msgs = build_messages(t["history"], t["user_msg"])
    resp = call_llm(msgs)
    print(f"Clara: {resp}")
    time.sleep(0.5)
