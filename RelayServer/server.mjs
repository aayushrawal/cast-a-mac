import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import { WebSocketServer, WebSocket } from "ws";

const port = Number(process.env.PORT ?? 8080);
const dataFile = process.env.DATA_FILE ?? "./relay-data.json";
const tokenSecret = process.env.RELAY_TOKEN_SECRET ?? crypto.randomUUID();
const tokenLifetimeSeconds = 60 * 60 * 24 * 180;

const store = loadStore();
const onlineHosts = new Map();
const clientsByHost = new Map();
const webSockets = new WebSocketServer({ noServer: true });

const server = http.createServer(async (request, response) => {
  setCommonHeaders(response);

  if (request.method === "GET" && request.url === "/health") {
    sendJSON(response, 200, {
      status: "ok",
      onlineHosts: onlineHosts.size
    });
    return;
  }

  if (request.method === "POST" && request.url === "/v1/link") {
    try {
      const body = await readJSON(request);
      const code = String(body.code ?? "").trim().toUpperCase();
      const match = [...onlineHosts.entries()].find(([, value]) =>
        timingSafeEqual(value.linkCode, code)
      );
      if (!match) {
        sendJSON(response, 404, { error: "link_code_not_found" });
        return;
      }

      const [hostID, host] = match;
      sendJSON(response, 200, {
        host: {
          id: hostID,
          name: host.name,
          isOnline: true,
          lastSeenAt: new Date().toISOString()
        },
        accessToken: createClientToken(hostID)
      });
    } catch {
      sendJSON(response, 400, { error: "invalid_request" });
    }
    return;
  }

  sendJSON(response, 404, { error: "not_found" });
});

server.on("upgrade", (request, socket, head) => {
  try {
    const url = new URL(request.url, "http://relay.invalid");
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts.length !== 3 || parts[0] !== "v1") {
      rejectUpgrade(socket, 404);
      return;
    }

    const [, role, hostID] = parts;
    const token = bearerToken(request);
    if (role === "host") {
      authorizeHost(request, hostID, token);
    } else if (role === "client") {
      verifyClientToken(token, hostID);
      if (!onlineHosts.has(hostID)) {
        rejectUpgrade(socket, 503);
        return;
      }
    } else {
      rejectUpgrade(socket, 404);
      return;
    }

    webSockets.handleUpgrade(request, socket, head, (webSocket) => {
      webSockets.emit("connection", webSocket, request, { role, hostID });
    });
  } catch {
    rejectUpgrade(socket, 401);
  }
});

webSockets.on("connection", (webSocket, request, context) => {
  const { role, hostID } = context;

  if (role === "host") {
    const name = header(request, "x-cast-host-name") || "Mac";
    const linkCode = header(request, "x-cast-link-code").toUpperCase();
    const previous = onlineHosts.get(hostID)?.socket;
    previous?.close(4001, "Replaced by a newer host connection");
    onlineHosts.set(hostID, {
      socket: webSocket,
      name,
      linkCode,
      latestConfiguration: undefined
    });

    webSocket.on("message", (data, isBinary) => {
      if (!isBinary) return;
      const packet = Buffer.from(data);
      if (
        packet.length >= 6 &&
        packet.subarray(0, 4).toString("ascii") === "CAST" &&
        packet[5] === 1
      ) {
        const host = onlineHosts.get(hostID);
        if (host?.socket === webSocket) {
          host.latestConfiguration = packet;
        }
      }
      for (const client of clientsByHost.get(hostID) ?? []) {
        if (client.readyState === WebSocket.OPEN) {
          client.send(data, { binary: true });
        }
      }
    });
    webSocket.on("close", () => {
      if (onlineHosts.get(hostID)?.socket === webSocket) {
        onlineHosts.delete(hostID);
      }
    });
    return;
  }

  const clients = clientsByHost.get(hostID) ?? new Set();
  clients.add(webSocket);
  clientsByHost.set(hostID, clients);
  const configuration = onlineHosts.get(hostID)?.latestConfiguration;
  if (configuration) {
    webSocket.send(configuration, { binary: true });
  }

  webSocket.on("message", (data, isBinary) => {
    if (!isBinary) return;
    const host = onlineHosts.get(hostID)?.socket;
    if (host?.readyState === WebSocket.OPEN) {
      host.send(data, { binary: true });
    }
  });
  webSocket.on("close", () => {
    clients.delete(webSocket);
    if (clients.size === 0) {
      clientsByHost.delete(hostID);
    }
  });
});

server.listen(port, () => {
  console.log(`Cast-a-mac relay listening on port ${port}`);
});

function authorizeHost(request, hostID, token) {
  if (!isUUID(hostID) || token.length < 32) {
    throw new Error("Invalid host credentials");
  }
  const secretHash = sha256(token);
  const existing = store.hosts[hostID];
  if (existing && !timingSafeEqual(existing.secretHash, secretHash)) {
    throw new Error("Invalid host secret");
  }
  store.hosts[hostID] = {
    secretHash,
    name: header(request, "x-cast-host-name") || existing?.name || "Mac"
  };
  saveStore();
}

function createClientToken(hostID) {
  const expiresAt = Math.floor(Date.now() / 1000) + tokenLifetimeSeconds;
  const payload = `${hostID}.${expiresAt}`;
  const signature = crypto
    .createHmac("sha256", tokenSecret)
    .update(payload)
    .digest("base64url");
  return `${payload}.${signature}`;
}

function verifyClientToken(token, expectedHostID) {
  const [hostID, expiresAtText, signature] = token.split(".");
  const expiresAt = Number(expiresAtText);
  if (
    hostID !== expectedHostID ||
    !Number.isFinite(expiresAt) ||
    expiresAt < Date.now() / 1000
  ) {
    throw new Error("Expired client token");
  }
  const payload = `${hostID}.${expiresAtText}`;
  const expected = crypto
    .createHmac("sha256", tokenSecret)
    .update(payload)
    .digest("base64url");
  if (!timingSafeEqual(signature, expected)) {
    throw new Error("Invalid client token");
  }
}

function bearerToken(request) {
  const authorization = header(request, "authorization");
  if (!authorization.startsWith("Bearer ")) {
    throw new Error("Missing bearer token");
  }
  return authorization.slice("Bearer ".length);
}

function header(request, name) {
  const value = request.headers[name];
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function isUUID(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value
  );
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function timingSafeEqual(left, right) {
  const leftBuffer = Buffer.from(String(left));
  const rightBuffer = Buffer.from(String(right));
  return (
    leftBuffer.length === rightBuffer.length &&
    crypto.timingSafeEqual(leftBuffer, rightBuffer)
  );
}

function loadStore() {
  try {
    return JSON.parse(fs.readFileSync(dataFile, "utf8"));
  } catch {
    return { hosts: {} };
  }
}

function saveStore() {
  const temporary = `${dataFile}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify(store, null, 2));
  fs.renameSync(temporary, dataFile);
}

function setCommonHeaders(response) {
  response.setHeader("Content-Type", "application/json");
  response.setHeader("Cache-Control", "no-store");
}

function sendJSON(response, status, body) {
  response.writeHead(status);
  response.end(JSON.stringify(body));
}

async function readJSON(request) {
  const chunks = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > 64 * 1024) {
      throw new Error("Request too large");
    }
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function rejectUpgrade(socket, status) {
  socket.write(`HTTP/1.1 ${status} Unavailable\r\nConnection: close\r\n\r\n`);
  socket.destroy();
}
