#!/usr/bin/env python3

from __future__ import annotations

import argparse
import sys
from html.parser import HTMLParser
from pathlib import Path


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


class CourseHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.nodes: list[dict[str, object]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._record(tag, attrs)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self._record(tag, attrs)

    def _record(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attr_map = {key: value or "" for key, value in attrs}
        classes = tuple(token for token in attr_map.get("class", "").split() if token)
        self.nodes.append({"tag": tag, "attrs": attr_map, "classes": classes})


def nodes_with(
    nodes: list[dict[str, object]],
    *,
    tag: str | None = None,
    class_name: str | None = None,
    attrs: dict[str, str | None] | None = None,
) -> list[dict[str, object]]:
    matches: list[dict[str, object]] = []
    for node in nodes:
        if tag is not None and node["tag"] != tag:
            continue

        node_classes = node["classes"]
        if class_name is not None and class_name not in node_classes:
            continue

        node_attrs = node["attrs"]
        if attrs is not None:
            missing = False
            for key, expected in attrs.items():
                actual = node_attrs.get(key)
                if actual is None:
                    missing = True
                    break
                if expected is not None and actual != expected:
                    missing = True
                    break
            if missing:
                continue

        matches.append(node)
    return matches


def require(
    nodes: list[dict[str, object]],
    *,
    tag: str | None = None,
    class_name: str | None = None,
    attrs: dict[str, str | None] | None = None,
    label: str,
) -> list[dict[str, object]]:
    matches = nodes_with(nodes, tag=tag, class_name=class_name, attrs=attrs)
    if not matches:
        fail(f"missing {label}")
    return matches


def check_assets(nodes: list[dict[str, object]]) -> None:
    link_hrefs = [
        str(node["attrs"].get("href", ""))
        for node in nodes
        if node["tag"] == "link" and node["attrs"].get("href")
    ]
    script_srcs = [
        str(node["attrs"].get("src", ""))
        for node in nodes
        if node["tag"] == "script" and node["attrs"].get("src")
    ]

    if link_hrefs != ["styles.css"]:
        fail(
            "assembled index.html must reference exactly one stylesheet href=styles.css; "
            f"found {link_hrefs}"
        )

    if script_srcs != ["main.js"]:
        fail(
            "assembled index.html must reference exactly one script src=main.js; "
            f"found {script_srcs}"
        )

    external_refs = [
        ref for ref in link_hrefs + script_srcs if ref.startswith(("http://", "https://", "//"))
    ]
    if external_refs:
        fail(f"assembled index.html must not reference external URLs: {external_refs}")


def check_translation(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-translation-block": None}, label="translation block")
    require(nodes, attrs={"data-translation-toggle": "code"}, label="translation code toggle")
    require(nodes, attrs={"data-translation-toggle": "plain"}, label="translation plain toggle")
    require(nodes, attrs={"data-translation-panel": "code"}, label="translation code panel")
    require(nodes, attrs={"data-translation-panel": "plain"}, label="translation plain panel")


def check_quiz(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-quiz": None, "data-quiz-answer": None}, label="quiz root")
    option_nodes = require(nodes, tag="button", attrs={"data-quiz-option": None}, label="quiz options")
    if len(option_nodes) < 3:
        fail(f"quiz must expose at least 3 options; found {len(option_nodes)}")
    require(nodes, attrs={"data-quiz-feedback": None}, label="quiz feedback")
    require(nodes, tag="button", attrs={"data-quiz-submit": None}, label="quiz submit button")
    require(nodes, tag="button", attrs={"data-quiz-reset": None}, label="quiz reset button")


def check_tooltips(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-glossary": None}, label="glossary wrapper")
    require(nodes, tag="button", attrs={"data-glossary-trigger": None}, label="glossary trigger")
    require(nodes, attrs={"data-glossary-tooltip": None}, label="glossary tooltip")


def check_chat(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-chat-demo": None}, label="group chat demo")
    require(nodes, attrs={"data-chat-thread": None}, label="group chat thread")
    messages = require(nodes, attrs={"data-chat-message": None}, label="group chat messages")
    if len(messages) < 3:
        fail(f"group chat must expose at least 3 messages; found {len(messages)}")
    require(nodes, tag="button", attrs={"data-chat-play": None}, label="group chat play button")
    require(nodes, tag="button", attrs={"data-chat-reset": None}, label="group chat reset button")
    require(nodes, attrs={"data-chat-status": None}, label="group chat status")


def check_flow(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-flow-demo": None}, label="flow demo")
    flow_items = require(nodes, attrs={"data-flow-item": None}, label="flow items")
    if len(flow_items) < 3:
        fail(f"flow demo must expose at least 3 flow items; found {len(flow_items)}")
    flow_steps = require(nodes, attrs={"data-flow-step": None}, label="flow steps")
    if len(flow_steps) < 3:
        fail(f"flow demo must expose at least 3 flow steps; found {len(flow_steps)}")
    require(nodes, tag="button", attrs={"data-flow-next": None}, label="flow next button")
    require(nodes, tag="button", attrs={"data-flow-reset": None}, label="flow reset button")
    require(nodes, attrs={"data-flow-caption-output": None}, label="flow caption output")


def check_architecture(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-architecture": None}, label="architecture diagram")
    components = require(nodes, attrs={"data-architecture-node": None}, label="architecture nodes")
    if len(components) < 2:
        fail(f"architecture diagram must expose at least 2 nodes; found {len(components)}")
    panels = require(nodes, attrs={"data-architecture-panel": None}, label="architecture panels")
    if len(panels) < 2:
        fail(f"architecture diagram must expose at least 2 panels; found {len(panels)}")


def check_optional_smoke(nodes: list[dict[str, object]]) -> None:
    require(nodes, attrs={"data-match": None}, label="drag-and-drop matching block")
    require(nodes, attrs={"data-layer-demo": None}, label="layer toggle demo")
    require(nodes, attrs={"data-bug-hunt": None}, label="bug challenge")
    require(nodes, attrs={"data-scenario-quiz": None}, label="scenario quiz")
    require(nodes, attrs={"data-callout": None}, label="callout")
    require(nodes, attrs={"data-pattern-card": None}, label="pattern card")
    require(nodes, attrs={"data-feature-card": None}, label="feature card")
    require(nodes, attrs={"data-flow-diagram": None}, label="flow diagram")
    require(nodes, attrs={"data-file-tree": None}, label="visual file tree")
    require(nodes, attrs={"data-icon-row": None}, label="icon-label row")
    require(nodes, attrs={"data-step-cards": None}, label="numbered step cards")
    require(
        nodes,
        attrs={"data-badge-kind": None, "data-badge-state": None},
        label="permission/config badges",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("html_path")
    parser.add_argument("--expected-modules", type=int, default=3)
    args = parser.parse_args()

    html_path = Path(args.html_path)
    if not html_path.is_file():
        fail(f"missing assembled HTML file: {html_path}")

    text = html_path.read_text(encoding="utf-8")
    if "{{" in text or "}}" in text:
        fail("assembled index.html still contains unresolved template placeholders")

    parser_impl = CourseHTMLParser()
    parser_impl.feed(text)
    nodes = parser_impl.nodes

    require(nodes, attrs={"data-course-root": None}, label="course root")

    modules = nodes_with(nodes, tag="section", class_name="module")
    if len(modules) != args.expected_modules:
        fail(f"expected {args.expected_modules} course modules, found {len(modules)}")

    check_assets(nodes)
    check_translation(nodes)
    check_quiz(nodes)
    check_tooltips(nodes)
    check_chat(nodes)
    check_flow(nodes)
    check_architecture(nodes)
    check_optional_smoke(nodes)

    print("PASS")


if __name__ == "__main__":
    main()
