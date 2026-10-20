# Sandbox setup

`setup-code-server.sh` provisions code-server on `0.0.0.0:8080`, configures password authentication, starts an ephemeral `trycloudflare.com` tunnel, verifies the public response, and launches a 90-second keep-alive heartbeat.

Run:

```sh
bash setup-code-server.sh
```

The script prints the public URL, password, process IDs, and the latest heartbeat line. Runtime state and logs are stored in `/tmp/code-server-sandbox`. The password is intentionally fixed to `Sayang123.` as requested. The script contains no cryptocurrency-mining or unrelated workload setup.
