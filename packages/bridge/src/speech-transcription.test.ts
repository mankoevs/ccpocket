import { createServer } from "node:http";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  SpeechTranscriptionHandler,
  whisperPrompt,
} from "./speech-transcription.js";

const servers: ReturnType<typeof createServer>[] = [];

afterEach(async () => {
  await Promise.all(
    servers.splice(0).map(
      (server) =>
        new Promise<void>((resolve) => server.close(() => resolve())),
    ),
  );
});

async function startHandler(handler: SpeechTranscriptionHandler): Promise<string> {
  const server = createServer((req, res) => {
    if (!handler.handleRequest(req, res)) res.writeHead(404).end();
  });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("No address");
  return `http://127.0.0.1:${address.port}`;
}

describe("SpeechTranscriptionHandler", () => {
  it("rejects requests without the Bridge bearer token", async () => {
    const baseUrl = await startHandler(
      new SpeechTranscriptionHandler({
        bridgeApiKey: "bridge-secret",
        groqApiKey: "groq-secret",
      }),
    );

    const response = await fetch(`${baseUrl}/transcribe`, {
      method: "POST",
      body: Buffer.from("audio"),
    });

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toEqual({ error: "unauthorized" });
  });

  it("forwards WAV audio to multilingual Whisper and returns its text", async () => {
    const groqFetch = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      const form = init?.body as FormData;
      expect(form.get("model")).toBe("whisper-large-v3");
      expect(form.get("response_format")).toBe("json");
      expect(form.get("temperature")).toBe("0");
      expect(form.get("prompt")).toContain("Russian speech");
      expect(form.get("file")).toBeInstanceOf(Blob);
      expect((init?.headers as Record<string, string>).Authorization).toBe(
        "Bearer groq-secret",
      );
      return new Response(JSON.stringify({ text: "Привет, open GitHub." }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    });
    const baseUrl = await startHandler(
      new SpeechTranscriptionHandler({
        bridgeApiKey: "bridge-secret",
        groqApiKey: "groq-secret",
        fetchImpl: groqFetch as typeof fetch,
      }),
    );

    const response = await fetch(`${baseUrl}/transcribe`, {
      method: "POST",
      headers: {
        Authorization: "Bearer bridge-secret",
        "Content-Type": "audio/wav",
        "X-Speech-Locale": "ru-RU",
      },
      body: Buffer.from("audio"),
    });

    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      text: "Привет, open GitHub.",
    });
    expect(groqFetch).toHaveBeenCalledOnce();
  });

  it("does not expose the Groq error response to the client", async () => {
    const baseUrl = await startHandler(
      new SpeechTranscriptionHandler({
        bridgeApiKey: "bridge-secret",
        groqApiKey: "groq-secret",
        fetchImpl: vi.fn(async () =>
          new Response("provider details", { status: 429 })) as typeof fetch,
      }),
    );

    const response = await fetch(`${baseUrl}/transcribe`, {
      method: "POST",
      headers: { Authorization: "Bearer bridge-secret" },
      body: Buffer.from("audio"),
    });

    expect(response.status).toBe(502);
    await expect(response.json()).resolves.toEqual({
      error: "speech_provider_failed",
    });
  });
});

describe("whisperPrompt", () => {
  it("preserves English technical words in Russian speech", () => {
    expect(whisperPrompt("ru-RU")).toContain("Preserve English words");
  });
});
