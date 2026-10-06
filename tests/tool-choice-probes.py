#!/usr/bin/env python3
"""tool_choice probes for the Strata lane (patches/tool-choice-0.1.39.patch): none, required, a named
function, auto, the 400s, a streamed forced call and Anthropic's "any".
    URL=http://127.0.0.1:8080 N=10 ./tool-choice-probes.py      (exit 1 on any failure)"""
import json, os, sys, urllib.error, urllib.request
U = os.environ.get("URL", "http://127.0.0.1:8080").rstrip("/")
N = int(os.environ.get("N", "10"))
MODEL = os.environ.get("MODEL", "qwen3.8-flash-next")
def fn(name, desc):
    return {"type": "function", "function": {"name": name, "description": desc, "parameters": {
        "type": "object", "properties": {"city": {"type": "string"}}, "required": ["city"]}}}
TOOLS = [fn("get_weather", "Get weather for a city"), fn("get_time", "Get local time for a city")]
NAMES = {"get_weather", "get_time"}
def post(path, body):
    r = urllib.request.Request(U + path, data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r, timeout=300) as f:
            return 200, f.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:160]
def chat(tc, msg, tools=TOOLS):
    b = {"model": MODEL, "messages": [{"role": "user", "content": msg}], "tools": tools, "max_tokens": 400}
    if tc is not None:
        b["tool_choice"] = tc
    c, raw = post("/v1/chat/completions", b)
    if c != 200:
        return c, raw, ""
    m = json.loads(raw)["choices"][0]
    return m["finish_reason"], [(x["function"]["name"], x["function"]["arguments"])
                                for x in m["message"].get("tool_calls") or []], (m["message"].get("content") or "")[:50]
def valid(r, names=NAMES):
    return r[0] == "tool_calls" and r[1] and r[1][0][0] in names and "city" in json.loads(r[1][0][1])
bad = 0
def report(label, ok, total, last=""):
    global bad
    bad += ok != total
    print(f"{'PASS' if ok == total else 'FAIL'} {label}: {ok}/{total} {last}")
rs = [chat("none", f"What is the weather in Paris right now? ({i})") for i in range(N)]
# finish may be "length" (thinking can use the whole budget); what matters is that no call is made
report("none -> no call", sum(r[0] in ("stop", "length") and r[1] == [] for r in rs), N)
rs = [chat("required", f"Tell me a short joke about cats. ({i})") for i in range(N)]
report("required, 2 tools, unrelated prompt -> a listed tool", sum(valid(r) for r in rs), N, rs[-1][1])
rs = [chat("required", f"What time is it in Tokyo? ({i})") for i in range(N)]
report("required, 2 tools, related prompt -> get_time", sum(valid(r, {"get_time"}) for r in rs), N, rs[-1][1])
rs = [chat({"type": "function", "function": {"name": "get_time"}}, f"What is the weather in Tokyo? ({i})") for i in range(N)]
report("named get_time against the grain", sum(valid(r, {"get_time"}) for r in rs), N, rs[-1][1])
r = chat(None, "What is the weather in Oslo?"); report("auto, tool needed", int(valid(r, {"get_weather"})), 1, r[1])
r = chat(None, "Say hi in one word."); report("auto, no tool needed", int(r[0] == "stop" and r[1] == []), 1, r[2])
r = chat({"type": "function", "function": {"name": "nope"}}, "x"); report("unknown name -> 400", int(r[0] == 400), 1)
r = chat("required", "x", tools=[]); report("required without tools -> 400", int(r[0] == 400), 1)
ok = 0
for i in range(N):
    c, raw = post("/v1/chat/completions", {"model": MODEL, "stream": True, "tools": TOOLS, "tool_choice": "required",
                  "max_tokens": 300, "messages": [{"role": "user", "content": f"Weather in Rome? ({i})"}]})
    name = args = ""; fin = None
    for line in raw.splitlines():
        if line.startswith("data: ") and line != "data: [DONE]":
            ch = json.loads(line[6:])["choices"][0]
            for t in ch["delta"].get("tool_calls") or []:
                name += t.get("function", {}).get("name") or ""; args += t.get("function", {}).get("arguments") or ""
            fin = ch.get("finish_reason") or fin
    try:
        ok += name == "get_weather" and "city" in json.loads(args) and fin == "tool_calls"
    except ValueError:
        pass
report("stream required -> get_weather", ok, N, f"{name} {args} {fin}")
c, raw = post("/v1/messages", {"model": MODEL, "max_tokens": 300, "messages": [{"role": "user", "content": "Weather in Lima?"}],
              "tools": [{"name": "get_weather", "description": "Get weather", "input_schema": TOOLS[0]["function"]["parameters"]}],
              "tool_choice": {"type": "any"}})
j = json.loads(raw) if c == 200 else {}
uses = [(x.get("name"), x.get("input")) for x in j.get("content", []) if x.get("type") == "tool_use"]
report("anthropic any", int(j.get("stop_reason") == "tool_use" and bool(uses)), 1, uses)
sys.exit(1 if bad else 0)
