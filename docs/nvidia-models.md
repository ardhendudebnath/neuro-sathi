# NVIDIA models used by NEURO-SATHI

All calls go through the backend ([`backend/app/services/nvidia.py`](../backend/app/services/nvidia.py)). The `NVIDIA_API_KEY` never leaves the server. The routes use the paid-route rate limits and the monthly budget cap.

| Feature | Model | Setting | Language fit |
| --- | --- | --- | --- |
| Sathi companion replies | Sarvam-M | `SATHI_MODEL` | Hindi, Bengali and 9 more Indian languages |
| Safety check on every question and reply | Nemotron Safety Guard Multilingual 8B | `SAFETY_MODEL` | Hindi, English (9 in total) |
| Cloud speech-to-text (with consent) | Canary 1B ASR or Whisper Large V3 | `ASR_FUNCTION_ID` | Hindi and English hosted |
| Cloud text-to-speech | Magpie TTS Multilingual | `TTS_FUNCTION_ID` | Hindi and English |

Speech uses NVIDIA's hosted Riva gRPC endpoint and needs the optional `nvidia-riva-client` package. Without it, or over budget, the speech routes return 503 and the app uses on-device voice.

## Privacy rules

- Only the question text goes to the LLM: no names, reminders or memory-book content. Personal questions are answered locally from the user's own rows.
- Audio goes to the cloud only after the user turns on "Allow cloud voice". By default the app uses on-device speech recognition.
- The server stores which answer path was used (local, LLM, fallback, safety block), not the question.

## Language coverage

Each language pack says whether the hosted companion model supports it (`meta.llm` in `content/language-packs`). Sarvam-M covers Hindi and Bengali but not Assamese or Nepali, so for those Sathi answers everyday questions from the pack and gives its scripted fallback for anything else, instead of sending the question to a model that cannot answer in the user's language.

## Known gap

None of these hosted models covers Assamese, Nepali, Manipuri (Meitei), Bodo or other NER languages yet. Options to evaluate:

- self-hosting Whisper Large V3 (covers Assamese and Bengali) on an India-region GPU server;
- Bhashini / AI4Bharat models (IndicTrans2, IndicConformer, Indic Parler-TTS) for NER languages.

The free build.nvidia.com API is for prototyping. For production, either self-host the open models in India or move to a paid plan.
