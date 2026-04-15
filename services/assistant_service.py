import json
import re
from functools import lru_cache
from typing import Any

from config import BASE_DIR, SUPPORTED_SOIL_TYPES


KNOWLEDGE_BASE_PATH = BASE_DIR / "data" / "assistant_knowledge.json"
FALLBACK_ANSWER = (
    "I do not have enough basis from the current farm knowledge base to answer that "
    "confidently. Please ask about soil type, crop suitability, fertilizer, planting "
    "conditions, or productivity."
)

INTENT_KEYWORDS = {
    "soil_type": {
        "soil",
        "soil type",
        "clay",
        "clay loam",
        "loam",
        "silty clay",
        "rock land",
        "explain",
        "meaning",
    },
    "crop_recommendation": {
        "crop",
        "crops",
        "recommend",
        "recommendation",
        "suitable",
        "suitability",
        "plant",
        "grow",
    },
    "fertilizer_guidance": {
        "fertilizer",
        "fertiliser",
        "compost",
        "manure",
        "npk",
        "spray",
        "apply",
    },
    "soil_management": {
        "manage",
        "management",
        "mulch",
        "drainage",
        "erosion",
        "organic matter",
        "compaction",
        "tillage",
    },
    "planting_climate": {
        "planting",
        "weather",
        "climate",
        "rain",
        "wind",
        "heat",
        "temperature",
        "seedling",
        "fieldwork",
    },
    "productivity": {
        "productivity",
        "yield",
        "harvest",
        "output",
        "record",
        "performance",
    },
}

STOPWORDS = {
    "a",
    "about",
    "an",
    "and",
    "are",
    "be",
    "best",
    "can",
    "for",
    "from",
    "how",
    "i",
    "in",
    "is",
    "it",
    "me",
    "my",
    "of",
    "on",
    "or",
    "should",
    "tell",
    "the",
    "to",
    "what",
    "when",
    "which",
    "with",
}

SOIL_PATTERNS = [
    (
        soil_type,
        re.compile(rf"\b{re.escape(soil_type.lower())}\b"),
    )
    for soil_type in sorted(SUPPORTED_SOIL_TYPES, key=len, reverse=True)
]


def chat_with_assistant(
    question: str,
    context: dict[str, Any] | None = None,
    history: list[dict[str, Any] | str] | None = None,
) -> dict:
    normalized_question = _normalize_text(question)
    if not normalized_question:
        return _fallback_response(context, "Assistant question is empty after normalization.")

    knowledge_entries = _load_assistant_knowledge()
    if not knowledge_entries:
        return _fallback_response(context, "Assistant knowledge base is unavailable.")

    history_text = _extract_history_text(history)
    context_text = _flatten_to_text(context)
    search_text = " ".join(part for part in [normalized_question, history_text] if part).strip()

    detected_soil_types = _detect_soil_types(search_text, context_text)
    detected_intents = _detect_intents(search_text, context_text)
    question_tokens = _tokenize(search_text)
    context_tokens = _tokenize(context_text)

    scored_entries = []
    for entry in knowledge_entries:
        score, signals = _score_entry(
            entry=entry,
            question_text=search_text,
            question_tokens=question_tokens,
            context_text=context_text,
            context_tokens=context_tokens,
            detected_intents=detected_intents,
            detected_soil_types=detected_soil_types,
        )
        if score > 0:
            scored_entries.append(
                {
                    "entry": entry,
                    "score": score,
                    "signals": signals,
                }
            )

    ranked_entries = sorted(
        scored_entries,
        key=lambda item: (
            item["score"],
            item["signals"]["keyword_hits"],
            item["signals"]["soil_match"],
            item["signals"]["context_match"],
        ),
        reverse=True,
    )

    selected_entries = _select_entries(ranked_entries)
    if not _has_confident_grounding(selected_entries):
        return _fallback_response(context, "No strong grounded match was found in the local knowledge base.")

    matched_topics = [item["entry"]["title"] for item in selected_entries]
    answer = _build_answer(selected_entries, detected_intents, detected_soil_types)

    if not answer:
        return _fallback_response(context, "Retrieved entries did not produce a grounded answer.")

    return {
        "status": "grounded",
        "answer": answer,
        "matched_topics": matched_topics,
        "used_context": context,
        "message": f"Grounded from: {', '.join(matched_topics)}.",
    }


@lru_cache(maxsize=1)
def _load_assistant_knowledge() -> list[dict[str, Any]]:
    try:
        with KNOWLEDGE_BASE_PATH.open("r", encoding="utf-8") as file:
            data = json.load(file)
    except (FileNotFoundError, json.JSONDecodeError):
        return []

    return data if isinstance(data, list) else []


def _normalize_text(text: Any) -> str:
    if text is None:
        return ""
    cleaned = re.sub(r"[^a-z0-9\s]", " ", str(text).lower())
    return re.sub(r"\s+", " ", cleaned).strip()


def _tokenize(text: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9]+", text)
        if token and token not in STOPWORDS
    }


def _flatten_to_text(value: Any) -> str:
    parts: list[str] = []

    def _collect(item: Any) -> None:
        if item is None:
            return
        if isinstance(item, str):
            parts.append(item)
            return
        if isinstance(item, dict):
            for key, nested_value in item.items():
                parts.append(str(key))
                _collect(nested_value)
            return
        if isinstance(item, (list, tuple, set)):
            for nested_value in item:
                _collect(nested_value)
            return
        parts.append(str(item))

    _collect(value)
    return _normalize_text(" ".join(parts))


def _extract_history_text(history: list[dict[str, Any] | str] | None) -> str:
    if not history:
        return ""

    snippets: list[str] = []
    for item in history[-4:]:
        if isinstance(item, str):
            snippets.append(item)
            continue
        if isinstance(item, dict):
            for key in ("question", "answer", "content", "message", "text"):
                value = item.get(key)
                if isinstance(value, str):
                    snippets.append(value)

    return _normalize_text(" ".join(snippets))


def _detect_soil_types(*texts: str) -> list[str]:
    combined_text = " ".join(part for part in texts if part).strip()
    if not combined_text:
        return []

    matches: list[str] = []
    used_spans: list[tuple[int, int]] = []
    for soil_type, pattern in SOIL_PATTERNS:
        for match in pattern.finditer(combined_text):
            start, end = match.span()
            overlaps = any(not (end <= span_start or start >= span_end) for span_start, span_end in used_spans)
            if overlaps:
                continue
            used_spans.append((start, end))
            matches.append(soil_type)

    return matches


def _detect_intents(*texts: Any) -> set[str]:
    combined_text = " ".join(_normalize_text(text) for text in texts if text).strip()
    if not combined_text:
        return set()

    intents = set()
    for category, keywords in INTENT_KEYWORDS.items():
        if any(_keyword_in_text(combined_text, keyword) for keyword in keywords):
            intents.add(category)

    return intents


def _keyword_in_text(text: str, keyword: str) -> bool:
    normalized_keyword = _normalize_text(keyword)
    if not normalized_keyword:
        return False
    if " " in normalized_keyword:
        return normalized_keyword in text
    return re.search(rf"\b{re.escape(normalized_keyword)}\b", text) is not None


def _score_entry(
    entry: dict[str, Any],
    question_text: str,
    question_tokens: set[str],
    context_text: str,
    context_tokens: set[str],
    detected_intents: set[str],
    detected_soil_types: list[str],
) -> tuple[int, dict[str, int | bool]]:
    keywords = entry.get("keywords") or []
    related_soil_types = set(entry.get("related_soil_types") or [])
    entry_category = entry.get("category", "")

    keyword_hits = sum(1 for keyword in keywords if _keyword_in_text(question_text, keyword))

    if keyword_hits == 0 and keywords:
        keyword_hits = len(question_tokens & _tokenize(" ".join(str(keyword) for keyword in keywords)))

    category_match = entry_category in detected_intents
    soil_match = bool(related_soil_types & set(detected_soil_types))

    context_match = 0
    if context_text:
        if any(_keyword_in_text(context_text, keyword) for keyword in keywords):
            context_match += 1
        if related_soil_types & set(_detect_soil_types(context_text)):
            context_match += 2
        if context_tokens & _tokenize(entry_category.replace("_", " ")):
            context_match += 1

    title_match = _keyword_in_text(question_text, entry.get("title", ""))

    score = 0
    score += min(keyword_hits, 3) * 2
    if category_match:
        score += 3
    if soil_match:
        score += 4
    score += context_match
    if title_match:
        score += 1

    return score, {
        "keyword_hits": keyword_hits,
        "category_match": category_match,
        "soil_match": soil_match,
        "context_match": context_match,
    }


def _select_entries(ranked_entries: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not ranked_entries:
        return []

    top_score = ranked_entries[0]["score"]
    selected: list[dict[str, Any]] = []
    seen_categories: set[str] = set()

    for item in ranked_entries:
        entry = item["entry"]
        category = entry.get("category", "")

        if item["score"] < 3:
            continue
        if selected and item["score"] < top_score - 4:
            continue
        if category in seen_categories and not item["signals"]["soil_match"]:
            continue

        selected.append(item)
        seen_categories.add(category)

        if len(selected) >= 3:
            break

    return selected


def _has_confident_grounding(selected_entries: list[dict[str, Any]]) -> bool:
    if not selected_entries:
        return False

    top_entry = selected_entries[0]
    top_signals = top_entry["signals"]
    strong_signal = (
        top_signals["keyword_hits"] > 0
        or bool(top_signals["soil_match"])
        or top_signals["context_match"] > 0
    )

    return top_entry["score"] >= 4 and strong_signal


def _build_answer(
    selected_entries: list[dict[str, Any]],
    detected_intents: set[str],
    detected_soil_types: list[str],
) -> str:
    ordered_entries = sorted(
        selected_entries,
        key=lambda item: (
            0 if item["signals"]["soil_match"] and item["entry"]["category"] == "soil_type" else 1,
            0 if item["entry"]["category"] in detected_intents else 1,
            -item["score"],
        ),
    )

    answer_parts: list[str] = []
    for item in ordered_entries:
        content = str(item["entry"].get("content", "")).strip()
        if not content or content in answer_parts:
            continue

        proposed_answer = " ".join(answer_parts + [content]).strip()
        if answer_parts and len(proposed_answer) > 520:
            break

        answer_parts.append(content)
        if len(answer_parts) >= 3:
            break

    answer = " ".join(answer_parts).strip()
    if detected_soil_types and answer and not any(soil_type.lower() in answer.lower() for soil_type in detected_soil_types):
        answer = f"For {detected_soil_types[0]} soil, {answer[0].lower() + answer[1:]}"

    return answer


def _fallback_response(context: dict[str, Any] | None, message: str) -> dict:
    return {
        "status": "fallback",
        "answer": FALLBACK_ANSWER,
        "matched_topics": [],
        "used_context": context,
        "message": message,
    }
