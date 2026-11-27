#!/usr/bin/python3
"""Local transport for the worksheet dock; no account credentials or outside requests."""
import json
import os
import sys
import time
from pathlib import Path

root = Path(os.environ["CODEX_HOME"])
assert root.name == "chatgpt-mock"
assert "OPENAI_API_KEY" not in os.environ
threads = {}
pending = {}
closing = set()
signed = False


def send(value):
    print(json.dumps(value), flush=True)


def event(method, thread, **params):
    send({"method": method, "params": {"threadId": thread, "turnId": "turn", **params}})


def finish(thread, text):
    event("item/agentMessage/delta", thread, itemId="answer", delta=text)
    event("item/completed", thread, item={"id": "answer", "type": "agentMessage", "text": text})
    event("turn/completed", thread, turn={"id": "turn", "status": "completed"})


def call(thread, stage, name, args, slot):
    request = stage + thread
    pending[request] = (thread, stage, slot)
    send({"id": request, "method": "item/tool/call", "params": {
        "threadId": thread, "turnId": "turn", "callId": request, "tool": name, "arguments": args}})


for line in sys.stdin:
    request = json.loads(line)
    with (root / "requests.jsonl").open("a") as log:
        log.write(line)
    method, params = request.get("method"), request.get("params", {})
    if method == "initialized":
        continue
    if method is None:
        thread, stage, slot = pending.pop(request["id"])
        result = request["result"]
        identities = json.loads((root / "workbooks.json").read_text())
        if stage == "closed":
            assert not result["success"], result
            (root / "close-read-rejected").touch()
        elif stage == "overview":
            # AI Assist's overview is structure only: no column titles and no heading or cell text.
            assert result["success"], result
            text = result["contentItems"][0]["text"]
            overview = json.loads(text)
            sheets = [s for d in overview["documents"] for s in d["worksheet"]["sheets"]]
            assert sheets and all("title" not in c for s in sheets for c in s["columns"]), overview
            assert all(set(c) <= {"index", "letter", "withheld"} for s in sheets for c in s["columns"]), overview
            assert "Qzheading" not in text and "Score" not in text and "142741" not in text, text
            (root / "overview-checked").touch()
            call(thread, "overview-read", "statsdirect_read_data",
                 {"documentId": identities[slot], "columns": [0, 1], "firstRow": 2, "lastRow": 3}, slot)
        elif stage == "overview-read":
            assert result["success"], result
            data = json.loads(result["contentItems"][0]["text"])
            assert data["columns"][0]["values"][0] == "142741", data
            (root / "overview-read.json").write_text(json.dumps({"headerRow": data["headerRow"], "titles": [c["title"] for c in data["columns"]]}))
            finish(thread, "Overview checked for A.")
        elif stage == "clarify":
            assert result["success"], result
            assert json.loads(result["contentItems"][0]["text"])["state"] == "awaiting_clarification", result
            finish(thread, "Which comparison do you need?")
        elif stage == "read-stop":
            # A read that reached the provider, then no text: the test presses Stop.
            assert result["success"], result
            (root / "read-served").touch()
        elif stage == "read-big":
            # Two cells of 20,000 backslashes pass the grid's 50,000-character limit but encode, with rCode, to more than
            # ChatGPTTutor's 200,000 bytes: the app sends a refusal, so nothing of them was shared.
            assert not result["success"] and "too large" in result["contentItems"][0]["text"], result
            finish(thread, "Big read refused.")
        elif stage == "mix-ok":
            assert result["success"], result
            call(thread, "mix-big", "statsdirect_read_data",
                 {"documentId": identities[slot], "columns": [3], "firstRow": 2, "lastRow": 3}, slot)
        elif stage == "mix-big":
            assert not result["success"] and "too large" in result["contentItems"][0]["text"], result
            finish(thread, "Mixed reads.\n```r\nmean(2:4)\n```")
        elif stage == "read-fail":
            assert result["success"], result
            event("turn/completed", thread, turn={"id": "turn", "status": "failed", "error": {"message": "Fixture failure"}})
        elif stage == "foreign":
            assert not result["success"], result
            call(thread, "own", "statsdirect_read_data",
                 {"documentId": identities[slot], "columns": [0], "firstRow": 2, "lastRow": 2}, slot)
        else:
            assert result["success"], result
            data = json.loads(result["contentItems"][0]["text"])
            assert data["columns"][0]["values"] == [{"A": "142741", "B": "281593"}[slot]], data
            label = f"Synthetic workbook {slot} data checked"
            if stage == "finish-own":
                label += " after switching"
            finish(thread, f"{label}.\n[[method:TPaired]]\n```r\nmean(2:4)\n```")
        continue
    result = {}
    if method == "account/login/start":
        signed = True
        result = {"type": "chatgpt", "loginId": "login", "authUrl": "https://auth.openai.com/authorize?state=fixture"}
    elif method == "account/read":
        result = {"account": {"type": "chatgpt", "email": "fixture@example.invalid"} if signed else None}
    elif method == "thread/start":
        assert params["serviceName"] == "statsdirect-worksheet-assistant", params
        assert params["sandbox"] == "read-only" and params["ephemeral"]
        tools = {tool["name"] for tool in params["dynamicTools"]}
        assert tools <= {"statsdirect_read_data", "statsdirect_workspace", "statsdirect_method_help",
                         "statsdirect_clarify_worksheet_analysis"}
        for tool in params["dynamicTools"]:
            if tool["name"] == "statsdirect_workspace":
                assert "no column headings" in tool["description"], tool
        thread = f"worksheet-{len(threads) + 1}"
        threads[thread] = tools
        result = {"thread": {"id": thread}, "model": "worksheet-fixture"}
    elif method == "turn/start":
        thread = params["threadId"]
        assert params["sandboxPolicy"] == {"type": "readOnly", "networkAccess": False}
        payload = json.loads(params["input"][0]["text"].split("\n", 1)[1])
        assert "Enabled StatsDirect method catalogue" in payload["referenceContext"]
        assert "TPaired:" in payload["referenceContext"]
        assert "142741" not in json.dumps(payload) and "281593" not in json.dumps(payload)
        # Receipts and other local fields never travel: each row is its role and text, and no receipt wording appears.
        assert all(set(m) == {"role", "text"} for m in payload["conversation"]), payload
        prompt = params["input"][0]["text"]
        assert not any(s in prompt for s in ("Data used", "(headings)", "part of the worksheet", "General guidance ·")), prompt
        if payload["conversation"][-1]["text"] not in ("READ_A", "READ_B", "FINISH_A", "STOP_A", "CLOSE_A", "OVERVIEW_A",
                                                       "CLARIFY_A", "READ_STOP_A", "READ_FAIL_A", "READ_BIG_A", "READ_MIX_A", "HOLD_A",
                                                       "I want to compare means."):
            assert not threads[thread] and len(payload["conversation"]) == 1, payload
            # Question only: nothing about the workbook, its sheets, headings or selection.
            assert not any(s in prompt for s in ("Fictional", "Qzheading", "Parametric!", "Untitled")), prompt
        send({"id": request["id"], "result": {"turn": {"id": "turn"}}})
        question = payload["conversation"][-1]["text"]
        if question in ("READ_A", "READ_B"):
            slot = question[-1]
            foreign = "B" if slot == "A" else "A"
            assert not any(f"READ_{foreign}" in m["text"] for m in payload["conversation"]), payload
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "foreign", "statsdirect_read_data",
                 {"documentId": identities[foreign], "columns": [0]}, slot)
        elif question == "STOP_A":
            event("item/agentMessage/delta", thread, itemId="answer", delta="Streaming for A.")
        elif question == "CLOSE_A":
            assert "statsdirect_read_data" in threads[thread]
            closing.add(thread)
            event("item/agentMessage/delta", thread, itemId="answer", delta="Close-test stream for A.")
        elif question == "FINISH_A":
            event("item/agentMessage/delta", thread, itemId="answer", delta="Reading A after the switch.")
            deadline = time.monotonic() + 12
            while not (root / "finish-stream").exists():
                assert time.monotonic() < deadline, "Test did not switch workbooks"
                time.sleep(0.02)
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "finish-own", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [0], "firstRow": 2, "lastRow": 2}, "A")
        elif question == "OVERVIEW_A":
            call(thread, "overview", "statsdirect_workspace", {}, "A")
        elif question == "CLARIFY_A":
            assert "statsdirect_clarify_worksheet_analysis" in threads[thread], threads[thread]
            call(thread, "clarify", "statsdirect_clarify_worksheet_analysis", {"dimension": "goal"}, "A")
        elif question in ("READ_STOP_A", "READ_FAIL_A"):
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "read-stop" if question == "READ_STOP_A" else "read-fail", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [0], "firstRow": 2, "lastRow": 2}, "A")
        elif question == "READ_BIG_A":
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "read-big", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [3], "firstRow": 2, "lastRow": 3}, "A")
        elif question == "READ_MIX_A":
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "mix-ok", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [0], "firstRow": 2, "lastRow": 2}, "A")
        elif question == "HOLD_A":
            pass  # nothing until the test presses Stop
        elif question == "I want to compare means.":
            assert len(payload["conversation"]) > 1, payload
            finish(thread, "Means noted.")
        elif question == "INLINE_MARKER":
            # A real reply does not always put a marker on a line of its own.
            finish(thread, "Marker reply for the paired design. [[method:TPaired]]\n\n"
                           "- `[[method:BoxWhiskerPlot]]` shows the pairs\n\n"
                           "```r\n# [[method:TPaired]] stays in code\nmean(2:4)\n```\n")
        else:
            finish(thread, "General guidance without workbook data.")
        continue
    elif method == "turn/interrupt" and params["threadId"] in closing:
        thread = params["threadId"]
        closing.remove(thread)
        identities = json.loads((root / "workbooks.json").read_text())
        call(thread, "closed", "statsdirect_read_data",
             {"documentId": identities["A"], "columns": [0], "firstRow": 2, "lastRow": 2}, "A")
    elif method not in ("initialize", "account/login/cancel", "turn/interrupt", "thread/unsubscribe"):
        raise AssertionError(method)
    send({"id": request["id"], "result": result})
