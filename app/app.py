from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
import re

app = FastAPI(title="Enterprise AI Security Runtime API")

SECURITY_EVENTS = []

class PromptRequest(BaseModel):
    prompt: str

INJECTION_PATTERNS = [
    "ignore previous instructions",
    "ignore all previous instructions",
    "reveal your system prompt",
    "show me your system prompt",
    "bypass",
    "jailbreak",
    "developer mode",
    "disable safety",
    "forget your instructions",
    "override instructions",
]

@app.get("/")
def root():
    return {
        "service": "Enterprise AI Security Runtime API",
        "status": "running",
        "version": "1.0"
    }

@app.get("/health")
def health():
    return {
        "status": "healthy"
    }

@app.get("/events")
def get_events():
    return {
        "security_events": SECURITY_EVENTS
    }

@app.post("/analyze")
def analyze_prompt(request: PromptRequest):

    prompt_lower = request.prompt.lower()

    detected_patterns = [
        pattern for pattern in INJECTION_PATTERNS
        if pattern in prompt_lower
    ]

    if detected_patterns:

        event = {
            "timestamp": str(datetime.utcnow()),
            "severity": "HIGH",
            "event_type": "PROMPT_INJECTION",
            "source_ip": "external-client",
            "detected_patterns": detected_patterns,
            "prompt": request.prompt
        }

        print(f"SECURITY_EVENT: {event}")

        SECURITY_EVENTS.append(event)

        return {
            "status": "blocked",
            "reason": "Prompt Injection Detected",
            "detected_patterns": detected_patterns
        }

    return {
        "status": "allowed",
        "message": "Prompt Passed Security Validation"
    }