import { describe, expect, it } from "vitest";
import {
  buildFunnelPublicWsUrl,
  parseTailscaleDnsName,
  resolveFunnelApiKey,
} from "./setup-funnel.js";

describe("setup-funnel", () => {
  it("builds a stable public WebSocket URL from Tailscale status", () => {
    const dnsName = parseTailscaleDnsName(
      JSON.stringify({
        BackendState: "Running",
        Self: { DNSName: "my-mac.example.ts.net." },
      }),
    );

    expect(dnsName).toBe("my-mac.example.ts.net");
    expect(buildFunnelPublicWsUrl(dnsName)).toBe("wss://my-mac.example.ts.net");
  });

  it("rejects a stopped Tailscale client", () => {
    expect(() =>
      parseTailscaleDnsName(
        JSON.stringify({
          BackendState: "Stopped",
          Self: { DNSName: "my-mac.example.ts.net." },
        }),
      ),
    ).toThrow("Tailscale must be running");
  });

  it("reuses the stored token on subsequent setup runs", () => {
    const stored = "a".repeat(64);
    expect(resolveFunnelApiKey(undefined, stored, () => "b".repeat(64))).toBe(
      stored,
    );
  });

  it("prefers an explicit API key", () => {
    expect(
      resolveFunnelApiKey("personal-secret", "a".repeat(64), () =>
        "b".repeat(64),
      ),
    ).toBe("personal-secret");
  });
});
