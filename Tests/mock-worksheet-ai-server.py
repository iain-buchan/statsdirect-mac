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
T_TEST = "statsdirect_choose_worksheet_t_test"
CLARIFY = "statsdirect_clarify_worksheet_analysis"
# Windows' tool (ScriptAIPane.cs) and its results: the card is staged, and nothing about the selection is returned.
T_TEST_TOOL = {"type": "function", "name": T_TEST,
               "description": "Open the Help decision tree for a quantitative comparison. Omit design when the study design is unclear. Use paired for matched pairs and independent for two independent samples. The card considers the relevant counts and distributions locally. This tool shares no diagnostic data and runs no analysis.",
               "inputSchema": {"type": "object", "properties": {"design": {"type": "string", "enum": ["paired", "independent"]}},
                               "required": [], "additionalProperties": False}}
DESIGN = {"state": "awaiting_design",
          "message": "Ask the user to choose “Same people or units” or “Separate groups” in the chat."}
DISTRIBUTION = {"state": "awaiting_distribution",
                "message": "The decision card lets the user check their selection locally and choose a branch. Ask them to review the card."}
# A card's wording stays on the Mac: none of it may reach the provider.
CARD_WORDS = ("Local check found", "Suggested branch", "Review the differences", "Shape check ·", "Suggested · ",
              "Use these as separate samples", "Change sample choice", "is not numeric")
SHARED = ("READ_A", "READ_B", "FINISH_A", "STOP_A", "CLOSE_A", "OVERVIEW_A", "CLARIFY_A", "READ_STOP_A", "READ_TEXT_STOP_A",
          "READ_FAIL_A", "READ_BIG_A", "READ_MIX_A", "READ_PLACEHOLDER_A", "HOLD_A", "I want to compare means.",
          "DESIGN_A", "PAIRED_A", "INDEPENDENT_A", "CLARIFY_THEN_CARD_A", "HOLD_CARD_A", "STOP_CARD_A", "AFTER_CARD_A", "NO_CARD_A",
          "FIXTURE_PAIRED_A", "FIXTURE_INDEPENDENT_A")


def private():
    # The workbook, sheet, heading and cell texts the test writes before a question-only send: none may travel.
    path = root / "private.json"
    return json.loads(path.read_text()) if path.exists() else []


def staged(result, expected):
    assert result["success"] and json.loads(result["contentItems"][0]["text"]) == expected, result


def refused(result, text):
    assert not result["success"] and result["contentItems"][0]["text"] == text, result


def send(value):
    print(json.dumps(value), flush=True)


def event(method, thread, **params):
    send({"method": method, "params": {"threadId": thread, "turnId": "turn", **params}})


def finish(thread, text):
    event("item/agentMessage/delta", thread, itemId="answer", delta=text)
    event("item/completed", thread, item={"id": "answer", "type": "agentMessage", "text": text})
    event("turn/completed", thread, turn={"id": "turn", "status": "completed"})


def call(thread, stage, name, args, slot, call_id=None):
    request = stage + thread
    pending[request] = (thread, stage, slot)
    send({"id": request, "method": "item/tool/call", "params": {
        "threadId": thread, "turnId": "turn", "callId": call_id or request, "tool": name, "arguments": args}})


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
        if threads[thread] <= {T_TEST}:
            # A question-only result carries nothing from the workbook either.
            assert not any(s in json.dumps(result, ensure_ascii=False) for s in private()), result
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
            # ... and the structure the model needs: names, extents, column letters and the active sheet's selection.
            assert all({"index", "name", "firstDataRow", "lastDataRow", "columnCount"} <= set(s) for s in sheets), overview
            assert all(c.get("letter") for s in sheets for c in s["columns"]), overview
            active = overview["documents"][0]["worksheet"]["activeSheet"]
            assert "selection" in next(s for s in sheets if s["index"] == active), overview
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
        elif stage == "clarify-bad":
            assert not result["success"] and "Choose goal, scale or design." in result["contentItems"][0]["text"], result
            call(thread, "clarify", "statsdirect_clarify_worksheet_analysis", {"dimension": "goal"}, slot)
        elif stage == "clarify":
            assert result["success"], result
            assert json.loads(result["contentItems"][0]["text"])["state"] == "awaiting_clarification", result
            call(thread, "clarify-again", "statsdirect_clarify_worksheet_analysis", {"dimension": "scale"}, slot)
        elif stage == "clarify-again":
            # One card per reply.
            assert not result["success"] and "already waiting" in result["contentItems"][0]["text"], result
            finish(thread, "Which comparison do you need?")
        elif stage == "text-stop":
            assert result["success"], result
            event("item/agentMessage/delta", thread, itemId="answer", delta="Partial text after a read.")
            (root / "text-streamed").touch()
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
        elif stage == "placeholder":
            assert result["success"], result
            data = json.loads(result["contentItems"][0]["text"])
            # C1 holds the text "Column C": a real heading that reads like the stand-in.
            assert [c["title"] for c in data["columns"]] == ["Column C"], data
            finish(thread, "Placeholder heading read.")
        elif stage == "read-fail":
            assert result["success"], result
            event("turn/completed", thread, turn={"id": "turn", "status": "failed", "error": {"message": "Fixture failure"}})
        elif stage == "foreign":
            assert not result["success"], result
            call(thread, "own", "statsdirect_read_data",
                 {"documentId": identities[slot], "columns": [0], "firstRow": 2, "lastRow": 2}, slot)
        elif stage == "design":
            staged(result, DESIGN)
            finish(thread, "Choose how the measurements were collected below.")
        elif stage == "paired-bad":
            # Windows' validation of design (ScriptAIPane.cs): a string paired or independent, and nothing else.
            refused(result, "Omit design or set it to paired or independent.")
            call(thread, "paired-extra", T_TEST, {"design": "paired", "columns": [0, 1]}, slot)
        elif stage == "paired-extra":
            refused(result, "Omit design or set it to paired or independent.")
            call(thread, "paired", T_TEST, {"design": "paired"}, slot)
        elif stage == "paired":
            staged(result, DISTRIBUTION)
            call(thread, "paired-again", T_TEST, {"design": "independent"}, slot)
        elif stage == "paired-again":
            # One staged card per reply, shared with the clarifying question.
            refused(result, "A worksheet action is already waiting.")
            call(thread, "paired-clarify", CLARIFY, {"dimension": "goal"}, slot)
        elif stage == "paired-clarify":
            refused(result, "A worksheet action is already waiting.")
            finish(thread, "Check the paired card below.")
        elif stage == "independent":
            staged(result, DISTRIBUTION)
            finish(thread, "Check the independent card below.")
        elif stage == "clarify-first":
            assert result["success"], result
            call(thread, "card-after-clarify", T_TEST, {}, slot)
        elif stage == "card-after-clarify":
            refused(result, "A worksheet action is already waiting.")
            finish(thread, "Which design?")
        elif stage == "hold-card":
            staged(result, DISTRIBUTION)
            event("item/agentMessage/delta", thread, itemId="answer", delta="Card staged; reply still running.")
            (root / "card-staged").touch()
            deadline = time.monotonic() + 12
            while not (root / "card-release").exists():
                assert time.monotonic() < deadline, "Test did not release the card reply"
                time.sleep(0.02)
            finish(thread, "Card staged; reply complete.")
        elif stage == "stop-card":
            # The reply stays open until the test presses Stop.
            staged(result, DISTRIBUTION)
            event("item/agentMessage/delta", thread, itemId="answer", delta="Card staged before Stop.")
            (root / "stop-card-staged").touch()
        elif stage == "qo-clarify":
            # Question only does not offer the clarifying question, so the tutor refuses it before the pane sees it, with
            # Windows' guidance-only text for its worksheet tools (ChatGPTTutor.cs:354, :365-369).
            refused(result, "The analysis proposal could not be staged.")
            call(thread, "qo-bad", T_TEST, {"design": "paired maybe"}, slot)
        elif stage == "qo-bad":
            # Windows' guidance-only text for any refusal of the card's tool.
            refused(result, "The analysis proposal could not be staged.")
            call(thread, "qo-card", T_TEST, {"design": "paired"}, slot)
        elif stage == "qo-card":
            staged(result, DISTRIBUTION)
            call(thread, "qo-again", T_TEST, {}, slot)
        elif stage == "qo-again":
            refused(result, "The analysis proposal could not be staged.")
            # The card's own tool refused by the tutor before the pane sees it (a repeated call): the same text.
            call(thread, "qo-repeat", T_TEST, {"design": "paired"}, slot, call_id="qo-card" + thread)
        elif stage == "qo-repeat":
            refused(result, "The analysis proposal could not be staged.")
            finish(thread, "Decision card offered without workbook data.")
        elif stage in ("fixture-paired", "fixture-independent"):
            # The preflight's cases are checked on the Mac; the result is the card's state and message, nothing of the selection.
            staged(result, DISTRIBUTION)
            finish(thread, "Check the fixture " + stage.split("-")[1] + " card below.")
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
        assert tools <= {"statsdirect_read_data", "statsdirect_workspace", "statsdirect_method_help", CLARIFY, T_TEST}
        for tool in params["dynamicTools"]:
            if tool["name"] == "statsdirect_workspace":
                assert "no column headings" in tool["description"], tool
            if tool["name"] == T_TEST:
                assert tool == T_TEST_TOOL, tool
        # The worksheet instructions the Mac sends: the clarification tool, the structure-only overview, no pasted data,
        # and Windows' sentences on the study-design card, with the question-only ones.
        assert all(s in params["baseInstructions"] for s in (CLARIFY, "but not column headings or cell values", "Never ask the user to paste",
                                                             T_TEST + " without arguments to offer Same people or units and Separate groups",
                                                             "pass design paired to the same tool", "pass design independent",
                                                             "The buttons collect the next details locally",
                                                             "It does not share workbook data or results.")), params["baseInstructions"][:300]
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
        assert not any(s in prompt for s in ("Data used", "(headings)", "part of the worksheet", "General guidance ·") + CARD_WORDS), prompt
        if payload["conversation"][-1]["text"] not in SHARED:
            # Question only: the study-design card's tool at most, which shares nothing, and the current question alone.
            assert threads[thread] <= {T_TEST} and len(payload["conversation"]) == 1, payload
            # Nothing about the workbook, its sheets, headings, selection or cells.
            request_text = json.dumps(params, ensure_ascii=False)
            assert not any(s in prompt for s in ("Fictional", "Qzheading", "Parametric!", "Untitled")), prompt
            assert not any(s in request_text for s in private()), request_text
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
            call(thread, "clarify-bad", "statsdirect_clarify_worksheet_analysis", {"dimension": "colour"}, "A")
        elif question in ("READ_STOP_A", "READ_TEXT_STOP_A", "READ_FAIL_A"):
            identities = json.loads((root / "workbooks.json").read_text())
            stage = {"READ_STOP_A": "read-stop", "READ_TEXT_STOP_A": "text-stop", "READ_FAIL_A": "read-fail"}[question]
            call(thread, stage, "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [0], "firstRow": 2, "lastRow": 2}, "A")
        elif question == "READ_BIG_A":
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "read-big", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [3], "firstRow": 2, "lastRow": 3}, "A")
        elif question == "READ_PLACEHOLDER_A":
            identities = json.loads((root / "workbooks.json").read_text())
            call(thread, "placeholder", "statsdirect_read_data",
                 {"documentId": identities["A"], "columns": [2], "firstRow": 2, "lastRow": 2}, "A")
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
        elif question == "DESIGN_A":
            assert T_TEST in threads[thread] and CLARIFY in threads[thread], threads[thread]
            call(thread, "design", T_TEST, {}, "A")
        elif question == "PAIRED_A":
            # As Windows' mock (tests/Learning/mock-server.mjs): an invalid design, an extra argument, then the card.
            call(thread, "paired-bad", T_TEST, {"design": "paired maybe"}, "A")
        elif question == "INDEPENDENT_A":
            call(thread, "independent", T_TEST, {"design": "independent"}, "A")
        elif question == "CLARIFY_THEN_CARD_A":
            call(thread, "clarify-first", CLARIFY, {"dimension": "design"}, "A")
        elif question in ("HOLD_CARD_A", "STOP_CARD_A"):
            call(thread, "hold-card" if question == "HOLD_CARD_A" else "stop-card", T_TEST, {"design": "paired"}, "A")
        elif question == "PAIRED_QO":
            # Question only offers exactly the card's tool (Windows GuidanceOnly: the clarifying question is not offered).
            assert threads[thread] == {T_TEST}, threads[thread]
            call(thread, "qo-clarify", CLARIFY, {"dimension": "design"}, "Q")
        elif question == "AFTER_CARD_A":
            # Choosing on a card adds nothing to the conversation.
            assert not any(m["text"] in ("Same people or units", "Separate groups") for m in payload["conversation"]), payload
            finish(thread, "Follow-up without the card.")
        elif question in ("FIXTURE_PAIRED_A", "FIXTURE_INDEPENDENT_A"):
            # Codex's preflight through the worksheet UI: one card of each design, staged for the selection the user makes.
            assert T_TEST in threads[thread] and CLARIFY in threads[thread], threads[thread]
            design = "paired" if question == "FIXTURE_PAIRED_A" else "independent"
            call(thread, "fixture-" + design, T_TEST, {"design": design}, "A")
        elif question in ("NO_CARD_A", "NO_CARD_QO"):
            # The workbook is not in front: no card is offered.
            assert T_TEST not in threads[thread], threads[thread]
            finish(thread, "No card offered.")
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
