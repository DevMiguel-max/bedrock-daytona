# Minecraft Bedrock on Daytona

🇬🇧 **English** · 🇧🇷 [Português](README.pt-BR.md)

Creates and runs a **Minecraft Bedrock** server on a Linux x86_64 sandbox (built for [Daytona](https://www.daytona.io)). Everything is driven by one file, `./mc`.

Two server types, chosen in `config.env`:

- **`bds` (default):** Mojang's official server. Always on the newest game version. It only runs on x86_64, which is why it could not run on Termux and can run here.
- **`pocketmine`:** PocketMine-MP (a community fork, because the official project stopped at 26.30).

## Read first: what Daytona prevents

This decides whether other people can join.

1. **Daytona only exposes HTTP.** Its "preview URLs" carry HTTP traffic, never UDP, and Minecraft Bedrock is UDP only. The only way for outsiders to join is a tunnel the sandbox opens outward (**playit**).
2. **Tier 1 and 2 have restricted outbound network** that cannot be lifted per sandbox. Only GitHub, package registries and some services work. **playit and Mojang are not on that list.**
3. **Tier 3 and 4 have open internet.** Per Daytona's docs, Tier 3 requires a verified business e-mail, a verified phone and a US$500 top-up.

Bottom line: on Tier 1 or 2 the server starts, but **nobody can join**. `./mc preflight` tells you in 10 seconds whether your sandbox reaches what it needs. If it reports blocked hosts, this option is not for you; use the Termux version or a PC.

Other Daytona limits: a sandbox defaults to 1 vCPU, 1 GB RAM and 3 GiB disk (max 4 vCPU, 8 GB, 10 GB per sandbox). It **auto-stops after 15 minutes** of inactivity, so you must change the default (step 1). Usage is billed; check the cost in the dashboard before leaving it on all day.

## Step by step

Run the commands **one at a time**.

### 1. Create the sandbox

Recommended: 2 vCPU, 4 GB RAM, 8 GB disk, **with auto-stop disabled** (value `0`). In the dashboard (app.daytona.io) set these fields on creation. With the Daytona CLI:

```bash
daytona create --auto-stop 0 --cpu 2 --disk 8
```

Memory has its own flag, but the docs I read are unclear on MB vs GB. Check with:

```bash
daytona create --help
```

If you already created it with the default (15 minutes), disable auto-stop through the API (replace `YOUR_KEY` and `YOUR_SANDBOX` with your API key and the sandbox name or ID):

```bash
curl -X POST -H "Authorization: Bearer YOUR_KEY" https://app.daytona.io/api/sandbox/YOUR_SANDBOX/autostop/0
```

(If your account has more than one organization, the API also wants an `X-Daytona-Organization-ID` header.)

### 2. Open a terminal in the sandbox

Use the **Web Terminal** in the Daytona dashboard. It is the simplest and needs nothing installed.

### 3. Get the project

Publish this folder to a GitHub repo of yours (GitHub is allowed on every Tier). Replace the address below with yours:

```bash
git clone https://github.com/DevMiguel-max/bedrock-daytona.git
```

```bash
cd bedrock-daytona
```

### 4. (Optional) Adjust the configuration

```bash
nano config.env
```

Most common: `SERVER_TYPE`, `SERVER_NAME`, `MAX_PLAYERS`, `VIEW_DISTANCE`. Server values only apply when `server.properties` is **created**.

### 5. Check that the network lets the server work

```bash
bash mc preflight
```

Reading the result:

- `github.com` must be **ok** (otherwise nothing downloads).
- `api.playit.gg` blocked = **nobody outside can join** (see "Read first").
- `minecraft-services.net` or `www.minecraft.net` blocked = the BDS cannot be downloaded. Use step 5b.

### 5b. Only if Mojang is blocked

Download the Linux server `.zip` at minecraft.net/en-us/download/server/bedrock, upload it to the sandbox, and put its path in `config.env`:

```bash
BDS_ZIP="/path/to/bedrock-server.zip"
```

Or switch to PocketMine, which only needs GitHub:

```bash
SERVER_TYPE="pocketmine"
```

### 6. Install and start

```bash
bash install.sh
```

It installs what is missing (curl, tar, unzip, tmux, jq), downloads the server and playit, creates `server.properties` and starts everything. If you are not root and have no `sudo`, it tells you what to install. To install without starting:

```bash
bash install.sh --no-start
```

### 7. Open internet access (playit)

```bash
./mc playit-setup
```

It prints a link. Open it **in your own browser**, sign in to playit and approve. Then, on playit.gg:

1. **Verify the account e-mail.** Until you do, the agent logs `account_status="email_not_verified"` and the tunnel does not work.
2. Create a **Minecraft Bedrock** tunnel with origin `127.0.0.1` port `19132`.

Restart:

```bash
./mc restart
```

The **public address is on the tunnel's Overview tab on the website**, not in the terminal. Use it in Minecraft → Servers → Add Server.

The dashboard may warn "Minecraft Bedrock requires RakNet" and suggest `transport=raknet`. In `bds` mode the script already writes that line to `server.properties`. In `pocketmine` mode ignore the warning: it only speaks RakNet.

## Daily use

Each command is independent.

Start the server:

```bash
./mc start
```

Stop it:

```bash
./mc stop
```

Restart it:

```bash
./mc restart
```

Running state, server version and address hint:

```bash
./mc status
```

Open the console (detach without stopping: `Ctrl+B`, then `D`):

```bash
./mc console
```

Last 200 console lines:

```bash
./mc logs
```

Backup (keeps the latest `BACKUP_KEEP`; on BDS it freezes writes so the backup is consistent):

```bash
./mc backup
```

Update the server (backs up first and preserves `server.properties` and worlds):

```bash
./mc update
```

Full diagnostics:

```bash
./mc doctor
```

See startup errors, in the foreground:

```bash
./mc run
```

### After the sandbox stops

Stopping the sandbox (manually or by limit) **kills the processes**; the files stay. After starting the sandbox again, open the terminal and run:

```bash
cd bedrock-daytona
```

```bash
./mc start
```

## Giving commands to a player

Without the `/`, from the terminal:

```bash
./mc cmd op YourName
```

```bash
./mc cmd gamemode creative YourName
```

```bash
./mc cmd give YourName diamond 64
```

```bash
./mc cmd list
```

The name is the Xbox gamertag. Names with spaces go in quotes: `./mc cmd op "Full Name"`. On BDS, to let in only people you approve, set `allow-list=true` in `server.properties` and use `./mc cmd allowlist add YourName`. In game, the same commands work with `/` once you are an operator.

## Players can't connect

1. `./mc status` prints the **server version**. Bedrock generally requires a version compatible with your game's.
2. `./mc doctor` shows library problems (BDS wants Ubuntu 22.04 or newer), playit and network issues.
3. `./mc playit-logs`: a lone IPv6 `Network unreachable` and a few `SessionNotSetup` lines right after connecting are normal. A `SessionNotSetup` loop that never stops is not.
4. `./mc logs` while trying: a login or outdated-version line means the packet arrived; nothing at all means it never reached the server.
5. Out of disk: `./mc backup` produces large files; lower `BACKUP_KEEP`.

## Security

`playit/secret` is the key to your tunnel account. It is already in `.gitignore` with `server/` and `backups/`; do not remove it. Daytona's preview token is a credential for the whole sandbox; do not share it.

## What was tested (and what wasn't)

**Tested on x86_64:** `pocketmine` mode end to end with the real PHP (download, 3 s boot, `op` through the console via tmux, backup with rotation, stop, restart, `doctor`). `bds` mode with a **fake** `bedrock_server`: zip install, `server.properties` writing, `save hold/query/resume`, update preserving your files and the crash-loop guard. `preflight` against a genuinely restricted network (GitHub open, playit and Mojang blocked). The playit Linux x86_64 binaries run and `claim` produces the link.

**Not tested:** nothing was run inside Daytona (no account or key). The **real** BDS download: the environment I tested in cannot reach Mojang, so the way the link is found (Mojang API, with the page as a fallback) follows what community scripts use and I did not confirm it. The real BDS running (Ubuntu version, libraries, memory use). `transport=raknet` comes from playit's tunnel page and was not verified on BDS. playit actually connecting, and a player actually joining.
