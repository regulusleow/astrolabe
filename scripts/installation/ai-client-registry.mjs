export class AIClientRegistry {
  #clients;

  constructor(clients) {
    this.#clients = new Map();
    for (const client of clients) {
      if (!client?.id) {
        throw new Error("Failed: AI client installer is missing an id");
      }
      if (this.#clients.has(client.id)) {
        throw new Error(`Failed: duplicate AI client installer: ${client.id}`);
      }
      this.#clients.set(client.id, client);
    }
  }

  resolve(clientIDs) {
    const clients = [];
    const seen = new Set();
    for (const clientID of clientIDs) {
      if (seen.has(clientID)) {
        continue;
      }
      const client = this.#clients.get(clientID);
      if (!client) {
        throw new Error(`Failed: unsupported AI client: ${clientID}`);
      }
      seen.add(clientID);
      clients.push(client);
    }
    return clients;
  }

  all() {
    return [...this.#clients.values()];
  }
}
