# Minecraft Bedrock no Daytona

🇬🇧 [English](README.md) · 🇧🇷 **Português**

Cria e roda um servidor **Minecraft Bedrock** em um sandbox Linux x86_64 (feito para o [Daytona](https://www.daytona.io)). Tudo é controlado por um único arquivo, o `./mc`.

Dois tipos de servidor, escolhidos em `config.env`:

- **`bds` (padrão):** o servidor oficial da Mojang. Sempre na versão mais nova do jogo. Só roda em x86_64, por isso não funcionava no Termux e funciona aqui.
- **`pocketmine`:** o PocketMine-MP (fork da comunidade, porque o oficial parou na 26.30).

## Leia antes: o que o Daytona impede

Isto decide se o servidor vai funcionar para outras pessoas.

1. **O Daytona só expõe HTTP.** As "preview URLs" aceitam tráfego HTTP, nunca UDP, e o Minecraft Bedrock usa só UDP. A única forma de alguém de fora entrar é um túnel que o sandbox abre para fora (o **playit**).
2. **Nos Tiers 1 e 2 a saída de rede é restrita** e não dá para liberar por sandbox. Só funcionam GitHub, repositórios de pacotes e alguns serviços. **O playit e a Mojang não estão nessa lista.**
3. **Tier 3 e 4 têm internet livre.** Segundo a documentação do Daytona, o Tier 3 exige e-mail empresarial verificado, telefone verificado e um depósito de US$ 500.

Conclusão: com o Tier 1 ou 2, o servidor até sobe, mas **ninguém consegue entrar**. O `./mc preflight` mostra em 10 segundos se o seu sandbox alcança o que precisa. Se o resultado for bloqueado, esta opção não serve para você, e a versão do Termux ou um PC é o caminho.

Outros limites do Daytona: o padrão do sandbox é 1 vCPU, 1 GB de RAM e 3 GiB de disco (máximo de 4 vCPU, 8 GB e 10 GB por sandbox). Ele **para sozinho após 15 minutos** sem atividade, e o padrão precisa ser trocado (passo 1). O uso é cobrado, então confira o custo no painel antes de deixar ligado o dia todo.

## Passo a passo

Rode os comandos **um de cada vez**.

### 1. Criar o sandbox

Recomendado: 2 vCPU, 4 GB de RAM e 8 GB de disco, **com o auto-stop desligado** (valor `0`). Pelo painel (app.daytona.io), ajuste esses campos ao criar. Pela CLI do Daytona:

```bash
daytona create --auto-stop 0 --cpu 2 --disk 8
```

A memória tem flag própria, mas a documentação que li não deixa claro se é em MB ou GB. Confira com:

```bash
daytona create --help
```

Se já criou o sandbox com o padrão (15 minutos), desligue o auto-stop pela API (troque `SUA_CHAVE` e `SEU_SANDBOX` pela chave de API e pelo nome ou ID do sandbox):

```bash
curl -X POST -H "Authorization: Bearer SUA_CHAVE" https://app.daytona.io/api/sandbox/SEU_SANDBOX/autostop/0
```

(Se a sua conta tiver mais de uma organização, a API também pede o cabeçalho `X-Daytona-Organization-ID`.)

### 2. Abrir um terminal no sandbox

Use o **Web Terminal** no painel do Daytona. É o mais simples e não precisa instalar nada.

### 3. Baixar o projeto

Publique esta pasta em um repositório seu no GitHub (o GitHub é liberado em todos os Tiers). Troque o endereço abaixo pelo seu:

```bash
git clone https://github.com/DevMiguel-max/bedrock-daytona.git
```

```bash
cd bedrock-daytona
```

### 4. (Opcional) Ajustar a configuração

```bash
nano config.env
```

Os pontos mais comuns: `SERVER_TYPE`, `SERVER_NAME`, `MAX_PLAYERS`, `VIEW_DISTANCE`. Os valores do servidor só valem na **criação** do `server.properties`.

### 5. Ver se a rede deixa o servidor funcionar

```bash
bash mc preflight
```

Leia o resultado:

- `github.com` precisa estar **ok** (senão nada é baixado).
- `api.playit.gg` bloqueado = **ninguém de fora entra** (veja "Leia antes").
- `minecraft-services.net` ou `www.minecraft.net` bloqueados = o BDS não pode ser baixado. Use o passo 5b.

### 5b. Só se a Mojang estiver bloqueada

Baixe o `.zip` do servidor Linux em minecraft.net/en-us/download/server/bedrock, envie para o sandbox, e no `config.env` ponha o caminho:

```bash
BDS_ZIP="/caminho/do/bedrock-server.zip"
```

Ou troque para o PocketMine, que só precisa do GitHub:

```bash
SERVER_TYPE="pocketmine"
```

### 6. Instalar e iniciar

```bash
bash install.sh
```

Ele instala o que falta (curl, tar, unzip, tmux, jq), baixa o servidor e o playit, cria o `server.properties` e liga tudo. Se você não for root nem tiver `sudo`, ele avisa o que instalar. Para instalar sem iniciar:

```bash
bash install.sh --no-start
```

### 7. Liberar o acesso pela internet (playit)

```bash
./mc playit-setup
```

Ele mostra um link. Abra **no seu navegador**, entre na conta playit e aprove. Depois, no site playit.gg:

1. **Confirme o e-mail da conta.** Sem isso o agente loga `account_status="email_not_verified"` e o túnel não funciona.
2. Crie um túnel **Minecraft Bedrock** com origem `127.0.0.1` e porta `19132`.

Reinicie:

```bash
./mc restart
```

O **endereço público aparece na aba Overview do túnel, no site**, e não no terminal. Use esse endereço em Minecraft → Servidores → Adicionar.

O painel pode avisar "Minecraft Bedrock requires RakNet" e sugerir `transport=raknet`. No modo `bds` o script já escreve essa linha no `server.properties`. No modo `pocketmine` ignore o aviso: ele só fala RakNet.

## Uso diário

Cada comando é independente.

Ligar o servidor:

```bash
./mc start
```

Desligar:

```bash
./mc stop
```

Reiniciar:

```bash
./mc restart
```

Ver se está rodando, a versão do servidor e dica do endereço:

```bash
./mc status
```

Abrir o console (sair sem parar: `Ctrl+B`, depois `D`):

```bash
./mc console
```

Ver as últimas 200 linhas do console:

```bash
./mc logs
```

Fazer backup (mantém os `BACKUP_KEEP` mais recentes; no BDS congela a escrita para o backup ficar consistente):

```bash
./mc backup
```

Atualizar o servidor (faz backup antes e preserva `server.properties` e mundos):

```bash
./mc update
```

Diagnóstico completo:

```bash
./mc doctor
```

Ver erros de inicialização, em primeiro plano:

```bash
./mc run
```

### Depois que o sandbox parar

Parar o sandbox (manual ou por limite) **encerra os processos**; os arquivos permanecem. Depois de iniciar o sandbox de novo, abra o terminal e rode:

```bash
cd bedrock-daytona
```

```bash
./mc start
```

## Dar comandos a um jogador

Sem a barra `/`, pelo terminal:

```bash
./mc cmd op SeuNick
```

```bash
./mc cmd gamemode creative SeuNick
```

```bash
./mc cmd give SeuNick diamond 64
```

```bash
./mc cmd list
```

O nick é o gamertag do Xbox. Nick com espaço vai entre aspas: `./mc cmd op "Nome Completo"`. No BDS, para só deixar entrar quem você autorizar, ligue `allow-list=true` no `server.properties` e use `./mc cmd allowlist add SeuNick`. Dentro do jogo os mesmos comandos funcionam com `/`, depois que você for operador.

## Jogadores não conectam

1. `./mc status` mostra a **versão do servidor**. O Bedrock geralmente exige versão compatível com a do jogo.
2. `./mc doctor` mostra problemas de bibliotecas (BDS pede Ubuntu 22.04 ou mais novo), do playit e de rede.
3. `./mc playit-logs`: um `Network unreachable` solto em IPv6 e algumas linhas `SessionNotSetup` logo ao conectar são normais. Um loop de `SessionNotSetup` que não para, não.
4. `./mc logs` durante a tentativa: uma linha de login ou de versão antiga significa que o pacote chegou; nada aparecer significa que não chegou ao servidor.
5. Sem espaço em disco: `./mc backup` gera arquivos grandes; ajuste `BACKUP_KEEP`.

## Segurança

`playit/secret` é a chave da sua conta de túnel. Já está no `.gitignore` junto com `server/` e `backups/`; não remova. O token de preview do Daytona é uma credencial do sandbox inteiro; não o compartilhe.

## O que foi testado (e o que não)

**Testado em ambiente x86_64:** o modo `pocketmine` de ponta a ponta com o PHP real (download, subida em 3 s, `op` pelo console via tmux, backup com rotação, parar, reiniciar, `doctor`). O modo `bds` com um `bedrock_server` **falso**: instalação por zip, escrita do `server.properties`, `save hold/query/resume`, atualização preservando seus arquivos e a proteção contra loop de queda. O `preflight` contra uma rede restrita de verdade (GitHub liberado, playit e Mojang bloqueados). Os binários do playit para Linux x86_64 rodam e o `claim` gera o link.

**Não testado:** nenhuma execução dentro do Daytona (não tenho conta nem chave). O download do BDS **real**: o ambiente onde testei não alcança a Mojang, então o jeito de achar o link (API da Mojang, com a página como reserva) segue o que scripts da comunidade usam e eu não confirmei. O BDS real rodando (versão do Ubuntu, bibliotecas, uso de memória). O `transport=raknet` vem da página do túnel do playit e não foi verificado no BDS. O playit conectando de fato, e um jogador entrando.
