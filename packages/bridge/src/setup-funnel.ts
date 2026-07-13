import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseBridgePort } from "./bridge-port.js";

const API_KEY_PATTERN = /^[a-f0-9]{64}$/;

interface TailscaleStatus {
  BackendState?: string;
  Self?: {
    DNSName?: string;
  };
}

export interface FunnelSetupOptions {
  port?: string;
  apiKey?: string;
}

export interface FunnelSetupResult {
  apiKey: string;
  port: string;
  publicWsUrl: string;
}

export function parseTailscaleDnsName(rawStatus: string): string {
  let status: TailscaleStatus;
  try {
    status = JSON.parse(rawStatus) as TailscaleStatus;
  } catch {
    throw new Error("Unable to parse `tailscale status --json` output");
  }

  if (status.BackendState !== "Running") {
    throw new Error("Tailscale must be running on the Bridge machine");
  }

  const dnsName = status.Self?.DNSName?.replace(/\.$/, "");
  if (!dnsName) {
    throw new Error("Tailscale MagicDNS is required for Funnel setup");
  }
  return dnsName;
}

export function buildFunnelPublicWsUrl(dnsName: string): string {
  return `wss://${dnsName.replace(/\.$/, "")}`;
}

export function resolveFunnelApiKey(
  explicitKey: string | undefined,
  storedKey: string | undefined,
  generate: () => string,
): string {
  const explicit = explicitKey?.trim();
  if (explicit) return explicit;

  const stored = storedKey?.trim();
  if (stored && API_KEY_PATTERN.test(stored)) return stored;

  const generated = generate();
  if (!API_KEY_PATTERN.test(generated)) {
    throw new Error("Generated Funnel API key is invalid");
  }
  return generated;
}

export function prepareFunnelSetup(
  opts: FunnelSetupOptions,
): FunnelSetupResult {
  const port = String(parseBridgePort(opts.port ?? process.env.BRIDGE_PORT));
  const status = execFileSync("tailscale", ["status", "--json"], {
    encoding: "utf8",
  });
  const dnsName = parseTailscaleDnsName(status);

  const configDir = join(homedir(), ".ccpocket");
  const apiKeyPath = join(configDir, "funnel-api-key");
  const storedKey = existsSync(apiKeyPath)
    ? readFileSync(apiKeyPath, "utf8")
    : undefined;
  const apiKey = resolveFunnelApiKey(
    opts.apiKey ?? process.env.BRIDGE_API_KEY,
    storedKey,
    () => randomBytes(32).toString("hex"),
  );

  if (!existsSync(configDir)) mkdirSync(configDir, { recursive: true });
  writeFileSync(apiKeyPath, `${apiKey}\n`, { mode: 0o600 });
  chmodSync(apiKeyPath, 0o600);

  console.log(`==> Enabling Tailscale Funnel for local port ${port}...`);
  try {
    execFileSync("tailscale", ["funnel", "--bg", port], {
      stdio: "inherit",
      timeout: 15_000,
    });
  } catch (err) {
    const timedOut =
      err instanceof Error &&
      "signal" in err &&
      (err as Error & { signal?: string }).signal === "SIGTERM";
    if (timedOut) {
      throw new Error(
        "Tailscale Funnel approval timed out. Approve Funnel in the URL printed by Tailscale, then run setup-funnel again.",
      );
    }
    throw err;
  }

  return {
    apiKey,
    port,
    publicWsUrl: buildFunnelPublicWsUrl(dnsName),
  };
}
