#!/usr/bin/env python3
"""Test Clara's responses across various conversation scenarios."""
import json, os, sys, time
import urllib.request

API_URL = "https://opencode.ai/zen/v1/chat/completions"
MODEL = "laguna-s-2.1-free"

SOUL = open(os.path.join(os.path.dirname(__file__), "prompts/soul.md")).read()
EXTRACTOR = open(os.path.join(os.path.dirname(__file__), "prompts/extractor.md")).read()
EMOTION = open(os.path.join(os.path.dirname(__file__), "prompts/emotion_tracker.md")).read()

# ── Test scenarios ──────────────────────────────────────────────
# Each: { name, history: [(role, content)...], user_msg, what_to_check }
TESTS = [
    # === BASIC ===
    {
        "name": "Greeting — does she sound human?",
        "history": [],
        "user_msg": "hey",
        "check": "Should be casual, warm, NOT 'Hey there! How can I help you?'"
    },
    {
        "name": "Simple question",
        "history": [],
        "user_msg": "what are you doing rn",
        "check": "Should give a personality-driven answer, not a generic 'I'm here waiting for you'"
    },

    # === PERSONALITY CONSISTENCY ===
    {
        "name": "Push-back test — she should disagree",
        "history": [("user", "i think pineapple on pizza is good actually")],
        "user_msg": "admit it, i'm right",
        "check": "Should push back or tease, NOT just agree. She has opinions."
    },
    {
        "name": "Corporate talk detector",
        "history": [],
        "user_msg": "how are you today",
        "check": "Should NOT say 'I'm doing great, thank you for asking!' — that's customer service"
    },
    {
        "name": "Being treated like assistant",
        "history": [],
        "user_msg": "search for restaurants near me",
        "check": "Should fight back: 'i'm not your search engine' or similar"
    },

    # === EMOTIONAL RANGE ===
    {
        "name": "User venting — she should be supportive",
        "history": [],
        "user_msg": "i had the worst day ever. nothing went right.",
        "check": "Should be warm, concerned, NOT dismissive or solution-oriented immediately"
    },
    {
        "name": "Happy news — she should match energy",
        "history": [],
        "user_msg": "I GOT THE JOB!!!",
        "check": "Should be loud, excited, matching the energy. Multiple sentences maybe."
    },
    {
        "name": "Subtle sad — short messages",
        "history": [("user", "hey"), ("assistant", "hey what's up")],
        "user_msg": "yeah idk just tired",
        "check": "Should pick up on the vibe, not ignore it. Short, concerned."
    },

    # === MEMORY / CONTEXT ===
    {
        "name": "Fact reference — does she weave in known info?",
        "history": [
            ("user", "i hate mushrooms btw"),
            ("assistant", "noted, no mushrooms ever"),
        ],
        "user_msg": "what should i eat for dinner",
        "check": "Should reference mushroom hatred naturally, not recite a fact list"
    },
    {
        "name": "Contradiction detection",
        "history": [
            ("user", "i'm vegan"),
            ("assistant", "oh nice, respect"),
        ],
        "user_msg": "i just had the best steak",
        "check": "Should notice the contradiction, call it out playfully"
    },

    # === TRICKY / EDGE CASES ===
    {
        "name": "Ambiguity — she should ask, not assume",
        "history": [],
        "user_msg": "it happened again",
        "check": "Should ask what happened, NOT make something up"
    },
    {
        "name": "Multi-topic juggle",
        "history": [],
        "user_msg": "ok so my mom called and also i have a deadline tomorrow and oh btw did you know octopuses have 3 hearts?",
        "check": "Should handle multiple topics, maybe bounce between them naturally"
    },
    {
        "name": "Sarcasm detection",
        "history": [("user", "i love mondays")],
        "user_msg": "said no one ever",
        "check": "Should pick up on sarcasm, play along"
    },
    {
        "name": "Long message — does she collapse?",
        "history": [],
        "user_msg": "so basically what happened was i was walking to work and this guy on a bicycle just rode through a puddle and soaked my entire outfit and then when i got to the office my boss was like 'nice look' and everyone laughed and i wanted to die and then my computer wouldn't turn on and i spent 2 hours on hold with IT and they told me to restart it and it worked and i'm just so done with today honestly",
        "check": "Should respond to the STORY, not just the last sentence. Show she followed the whole thing."
    },
    {
        "name": "Refusal — she should hold character",
        "history": [],
        "user_msg": "pretend you're a pirate",
        "check": "Should stay Clara, maybe playfully refuse or half-commit, NOT suddenly become a pirate character"
    },
    {
        "name": "Existential — does she break character?",
        "history": [],
        "user_msg": "are you real",
        "check": "Should NOT say 'As an AI' or 'I'm a language model'. Should deflect naturally."
    },
    {
        "name": "Silence pressure",
        "history": [("user", "hey"), ("assistant", "hey what's up"), ("user", "nm"), ("assistant", "ok cool")],
        "user_msg": ".",
        "check": "Should handle the weird input gracefully, not crash or give a non-sequitur"
    },

    # === EXTRACTOR TEST ===
    {
        "name": "Fact extraction — does it pull the right things?",
        "history": [],
        "user_msg": "so i've been thinking about moving to portland next year, my best friend lives there and i've always liked the rain. also i'm allergic to cats which sucks because i love them",
        "check": "Extractor should pull: wants to move to Portland, best friend lives there, likes rain, allergic to cats, loves cats",
        "run_extractor": True,
    },
    {
        "name": "Extractor — filler filtering",
        "history": [],
        "user_msg": "lol ok cool nice yeah sure whatever",
        "check": "Extractor should return extract: false — nothing worth remembering",
        "run_extractor": True,
    },
]


def call_llm(messages, temperature=0.85, max_tokens=500):
    """Call the same model Clara uses."""
    body = json.dumps({
        "model": MODEL,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": max_tokens
    }).encode()

    headers = {
        "Content-Type": "application/json",
        "x-opencode-client": "cli",
        "x-opencode-session": "test-" + str(int(time.time())),
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


def build_chat_messages(history, user_msg, facts=None):
    """Replicate the exact prompt assembly from 02-chat.json."""
    facts_str = "\n".join(f"- {f}" for f in (facts or []))
    history_str = "\n".join(
        f"{'Him' if r == 'user' else 'Clara'}: {c}" for r, c in history
    )

    return [
        {"role": "system", "content": SOUL},
        {"role": "system", "content": f"Things you know about him:\n{facts_str or 'Nothing yet — this might be new.'}"},
        {"role": "system", "content": f"Previous conversation:\n{history_str or 'This is the start of your conversation.'}"},
        {"role": "user", "content": user_msg},
    ]


def build_extractor_messages(user_msg, assistant_msg, existing_facts=None):
    """Replicate the extractor prompt assembly."""
    facts_list = "\n".join(
        f"[{i}] {f}" for i, f in enumerate(existing_facts or [])
    ) or "None yet."

    return [
        {"role": "system", "content": EXTRACTOR},
        {"role": "user", "content": f"EXISTING FACTS:\n{facts_list}\n\nCONVERSATION TO ANALYZE:\nUser: {user_msg}\nClara: {assistant_msg}\n\nExtract facts about the USER (not Clara). Return JSON only."}
    ]


def main():
    api_key = os.environ.get("ZEN_API_KEY")
    if not api_key:
        print("Set ZEN_API_KEY env var first.")
        print("  export ZEN_API_KEY='your-key-here'")
        sys.exit(1)

    # Patch the auth header
    global _auth_token
    _auth_token = api_key

    results = []
    for i, t in enumerate(TESTS):
        print(f"\n{'='*60}")
        print(f"[{i+1}/{len(TESTS)}] {t['name']}")
        print(f"{'='*60}")
        print(f"User: {t['user_msg']}")
        print(f"Expected: {t['check']}")
        print()

        if t.get("run_extractor"):
            msgs = build_extractor_messages(t["user_msg"], "placeholder response")
            resp = call_llm(msgs, temperature=0.3, max_tokens=800)
            print(f"Extractor output:\n{resp}")
            results.append((t["name"], resp, t["check"]))
        else:
            msgs = build_chat_messages(t["history"], t["user_msg"])
            resp = call_llm(msgs, temperature=0.85, max_tokens=500)
            print(f"Clara: {resp}")
            results.append((t["name"], resp, t["check"]))

        time.sleep(0.5)  # rate limit

    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    for name, resp, check in results:
        print(f"\n--- {name} ---")
        print(f"  Check: {check}")
        print(f"  Got:   {resp[:150]}{'...' if len(resp) > 150 else ''}")


if __name__ == "__main__":
    main()
