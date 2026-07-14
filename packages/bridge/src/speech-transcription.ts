import { timingSafeEqual } from "node:crypto";
import type { IncomingMessage, ServerResponse } from "node:http";

const MAX_AUDIO_BYTES = 25 * 1024 * 1024;
const DEFAULT_MODEL = "whisper-large-v3";
const GROQ_TRANSCRIPTIONS_URL =
  "https://api.groq.com/openai/v1/audio/transcriptions";

type FetchLike = typeof fetch;

interface SpeechTranscriptionOptions {
  bridgeApiKey?: string;
  groqApiKey?: string;
  model?: string;
  fetchImpl?: FetchLike;
}

function secureTokenEquals(actual: string | undefined, expected: string): boolean {
  if (!actual?.startsWith("Bearer ")) return false;
  const actualToken = Buffer.from(actual.slice("Bearer ".length));
  const expectedToken = Buffer.from(expected);
  return (
    actualToken.length === expectedToken.length &&
    timingSafeEqual(actualToken, expectedToken)
  );
}

async function readAudioBody(req: IncomingMessage): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;

  for await (const chunk of req) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > MAX_AUDIO_BYTES) {
      throw new Error("audio_too_large");
    }
    chunks.push(buffer);
  }

  return Buffer.concat(chunks);
}

export function whisperPrompt(locale: string | undefined): string {
  if (!locale || locale.toLowerCase().startsWith("ru")) {
    return "Transcribe Russian speech verbatim. Preserve English words, product names, code identifiers, and punctuation in English.";
  }
  return "Transcribe verbatim. Preserve product names, code identifiers, and punctuation in their original language.";
}

export class SpeechTranscriptionHandler {
  private readonly bridgeApiKey?: string;
  private readonly groqApiKey?: string;
  private readonly model: string;
  private readonly fetchImpl: FetchLike;

  constructor(options: SpeechTranscriptionOptions) {
    this.bridgeApiKey = options.bridgeApiKey;
    this.groqApiKey = options.groqApiKey;
    this.model = options.model ?? DEFAULT_MODEL;
    this.fetchImpl = options.fetchImpl ?? fetch;
  }

  handleRequest(req: IncomingMessage, res: ServerResponse): boolean {
    if (req.url !== "/transcribe" || req.method !== "POST") return false;
    void this.transcribe(req, res);
    return true;
  }

  private async transcribe(
    req: IncomingMessage,
    res: ServerResponse,
  ): Promise<void> {
    if (!this.bridgeApiKey || !this.groqApiKey) {
      this.sendJson(res, 503, { error: "speech_transcription_unavailable" });
      return;
    }
    if (!secureTokenEquals(req.headers.authorization, this.bridgeApiKey)) {
      this.sendJson(res, 401, { error: "unauthorized" });
      return;
    }

    try {
      const audio = await readAudioBody(req);
      if (audio.length === 0) {
        this.sendJson(res, 400, { error: "empty_audio" });
        return;
      }

      const contentType = req.headers["content-type"] ?? "audio/wav";
      const localeHeader = req.headers["x-speech-locale"];
      const locale = Array.isArray(localeHeader) ? localeHeader[0] : localeHeader;
      const form = new FormData();
      const audioBytes = Uint8Array.from(audio);
      form.append(
        "file",
        new Blob([audioBytes.buffer], { type: contentType }),
        "speech.wav",
      );
      form.append("model", this.model);
      form.append("prompt", whisperPrompt(locale));
      form.append("response_format", "json");
      form.append("temperature", "0");

      const response = await this.fetchImpl(GROQ_TRANSCRIPTIONS_URL, {
        method: "POST",
        headers: { Authorization: `Bearer ${this.groqApiKey}` },
        body: form,
        signal: AbortSignal.timeout(85_000),
      });
      if (!response.ok) {
        console.error(
          `[speech] Groq transcription failed with status ${response.status}`,
        );
        this.sendJson(res, 502, { error: "speech_provider_failed" });
        return;
      }

      const payload = (await response.json()) as { text?: unknown };
      const text = typeof payload.text === "string" ? payload.text.trim() : "";
      if (!text) {
        this.sendJson(res, 502, { error: "empty_transcription" });
        return;
      }
      this.sendJson(res, 200, { text });
    } catch (error) {
      if (error instanceof Error && error.message === "audio_too_large") {
        this.sendJson(res, 413, { error: "audio_too_large" });
        return;
      }
      console.error("[speech] Transcription request failed", error);
      this.sendJson(res, 500, { error: "speech_transcription_failed" });
    }
  }

  private sendJson(
    res: ServerResponse,
    status: number,
    body: Record<string, unknown>,
  ): void {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(body));
  }
}
