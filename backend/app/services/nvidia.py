"""NVIDIA build.nvidia.com clients. Only the backend holds the API key; the
apps call our routes, which are rate limited and budget capped."""

import json
import logging
import re

import httpx

from ..config import get_settings

log = logging.getLogger("neuro_sathi.nvidia")

_THINK = re.compile(r"<think>.*?</think>", re.DOTALL)

LANG_NAMES = {"en": "English", "hi": "Hindi", "bn": "Bengali", "as": "Assamese", "ne": "Nepali"}
# Riva language codes for Canary / Magpie. NER languages are not covered yet (see docs/nvidia-models.md).
RIVA_LANG = {"en": "en-US", "hi": "hi-IN"}


class NvidiaUnavailable(Exception):
    pass


def enabled() -> bool:
    return get_settings().nvidia_api_key is not None


def _chat(model: str, messages: list[dict], max_tokens: int, temperature: float = 0.3) -> str:
    s = get_settings()
    if s.nvidia_api_key is None:
        raise NvidiaUnavailable("NVIDIA_API_KEY not set")
    try:
        resp = httpx.post(
            f"{s.nvidia_base_url}/chat/completions",
            headers={"Authorization": f"Bearer {s.nvidia_api_key.get_secret_value()}"},
            json={"model": model, "messages": messages, "max_tokens": max_tokens, "temperature": temperature},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["choices"][0]["message"]["content"] or ""
    except (httpx.HTTPError, KeyError, IndexError, ValueError) as e:
        raise NvidiaUnavailable(str(e)) from e


def companion_reply(question: str, language: str) -> str:
    """Sarvam-M. Receives only the question: no names, reminders or health details."""
    lang = LANG_NAMES.get(language, "English")
    system = (
        "You are Sathi, a gentle companion for an elderly person in North-East India. "
        f"Reply in simple {lang} in at most three short sentences. Be warm and patient. "
        "Never diagnose, never give medicine doses, and suggest asking a family member or doctor "
        "for anything medical. If you are unsure, say so kindly."
    )
    text = _chat(
        get_settings().sathi_model,
        [{"role": "system", "content": system}, {"role": "user", "content": question}],
        max_tokens=300,
    )
    return _THINK.sub("", text).strip()


def is_safe(user_text: str, reply: str | None = None) -> bool:
    """Nemotron Safety Guard Multilingual. Fails closed: any error counts as unsafe."""
    messages = [{"role": "user", "content": user_text}]
    if reply is not None:
        messages.append({"role": "assistant", "content": reply})
    try:
        out = _chat(get_settings().safety_model, messages, max_tokens=100, temperature=0.0)
        verdict = json.loads(out[out.index("{") : out.rindex("}") + 1])
    except (NvidiaUnavailable, ValueError) as e:
        log.warning("safety check unavailable: %s", e)
        return False
    fields = ["User Safety"] + (["Response Safety"] if reply is not None else [])
    return all(str(verdict.get(f, "unsafe")).lower() == "safe" for f in fields)


def _riva_auth(function_id: str | None):
    s = get_settings()
    if s.nvidia_api_key is None or not function_id:
        raise NvidiaUnavailable("speech not configured")
    try:
        import riva.client  # optional dependency: nvidia-riva-client
    except ImportError as e:
        raise NvidiaUnavailable("nvidia-riva-client not installed") from e
    return riva.client, riva.client.Auth(
        uri=s.riva_grpc_uri,
        use_ssl=True,
        metadata_args=[
            ["function-id", function_id],
            ["authorization", f"Bearer {s.nvidia_api_key.get_secret_value()}"],
        ],
    )


def speech_to_text(audio: bytes, language: str) -> str:
    if language not in RIVA_LANG:
        raise NvidiaUnavailable(f"no hosted ASR for {language}")
    rc, auth = _riva_auth(get_settings().asr_function_id)
    try:
        asr = rc.ASRService(auth)
        config = rc.RecognitionConfig(language_code=RIVA_LANG[language], max_alternatives=1, enable_automatic_punctuation=True)
        resp = asr.offline_recognize(audio, config)
        return " ".join(r.alternatives[0].transcript for r in resp.results if r.alternatives).strip()
    except Exception as e:  # noqa: BLE001 - grpc errors vary
        raise NvidiaUnavailable(str(e)) from e


def text_to_speech(text: str, language: str) -> bytes:
    """Returns 16-bit mono PCM WAV."""
    if language not in RIVA_LANG:
        raise NvidiaUnavailable(f"no hosted TTS for {language}")
    rc, auth = _riva_auth(get_settings().tts_function_id)
    try:
        import io
        import wave

        tts = rc.SpeechSynthesisService(auth)
        rate = 22050
        resp = tts.synthesize(text, language_code=RIVA_LANG[language], sample_rate_hz=rate)
        buf = io.BytesIO()
        with wave.open(buf, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(resp.audio)
        return buf.getvalue()
    except Exception as e:  # noqa: BLE001
        raise NvidiaUnavailable(str(e)) from e
