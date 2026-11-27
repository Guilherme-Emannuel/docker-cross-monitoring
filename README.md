# Monitoramento cruzado com Docker (Zabbix + Grafana)

Template de referência para monitoramento de infraestrutura híbrida
(Linux + Windows) em rede privada, com foco em segurança de rede
outbound-first e baixo consumo de recursos.

## Arquitetura

```
Servidor A (Zabbix Server + Zabbix Web + Grafana + MySQL)
   ├── monitora → Servidor B (Linux, via Zabbix Agent2 em modo ativo)
   └── monitora → Servidor C (Windows, via Zabbix Agent2 em modo ativo)
```

- **Servidor A**: hospeda o Zabbix Server, Zabbix Web, MySQL e Grafana.
  Recebe métricas dos outros dois hosts via agentes em **modo ativo**
  (eles empurram os dados, o servidor não precisa iniciar conexão).
- **Servidor B**: host Linux com Zabbix Agent2, reportando métricas de
  sistema (CPU, memória, disco, rede).
- **Servidor C**: host **Windows**, com Zabbix Agent2 instalado
  nativamente (sem Docker, para reduzir overhead numa máquina de
  produção) — inclui workarounds documentados para bugs conhecidos do
  Agent2 no Windows.

## Por que modo ativo em vez de passivo

Em modo passivo (padrão), o Zabbix Server precisa iniciar conexão com
cada agent — exigindo porta de entrada aberta em cada host monitorado.
Em modo ativo, é o agent quem se conecta ao servidor para entregar os
dados. Isso significa **zero portas de entrada abertas** nos hosts
monitorados, reduzindo a superfície de ataque.

## Stack

Docker Compose · Zabbix 7.0 LTS · Grafana · MySQL 8.0

## Estrutura

```
.
├── server-a-zabbix-grafana/   # Zabbix Server + Web + Grafana + MySQL
│   ├── docker-compose.yml
│   ├── .env.example
│   └── scripts/
│       └── hardening-ufw.sh
├── server-b-linux-agent/      # Zabbix Agent2 (Linux)
│   ├── docker-compose.yml
│   ├── .env.example
│   └── scripts/
│       └── hardening-ufw.sh
├── server-c-windows-agent/    # Zabbix Agent2 (Windows, instalação nativa)
│   └── install-notes.md
├── grafana-dashboards/        # Dashboard Grafana pronto para importar
│   ├── Painel_Monitoramento.json
│   └── README.md               # passo a passo de import + troubleshooting
├── scripts/                    # Utilitários reutilizáveis entre os 3 servidores
│   ├── fix-vm-clock.sh         # corrige deriva de relógio em VMs (chrony)
│   └── README.md
└── webhooks/                   # Zabbix/Kuma → n8n (em construção, próxima etapa)
```

## Uso

Em cada servidor:

```bash
cp .env.example .env
# edite o .env com os valores reais do seu ambiente
chmod 600 .env
docker compose up -d
```

No **Servidor A**, antes do primeiro `up`, dê a pasta de dados do Grafana
ao usuário do container (UID 472):

```bash
mkdir -p data/grafana && sudo chown -R 472:472 data/grafana
```

Depois de subir, no Zabbix Web:

- troque a senha padrão do `Admin`;
- no host "Zabbix server", aponte a interface do agent para o DNS
  `zbx-agent-a` (o nome do container), não `127.0.0.1`;
- cadastre os hosts B e C com o **Host name igual ao `ZBX_HOSTNAME` /
  `Hostname`** do agent (no modo ativo, nome diferente = dados recusados)
  e a interface por **IP** (nomes de container de outro servidor não
  resolvem no Servidor A);
- crie um usuário só leitura para o Grafana, em vez de usar o `Admin`.

Depois, rode o script de hardening correspondente (requer `ufw`):

```bash
SERVER_B_IP=<ip> ADMIN_SSH_SOURCE=<subnet> ./scripts/hardening-ufw.sh
```

### Dashboard Grafana

O arquivo em `grafana-dashboards/Painel_Monitoramento.json` é o painel completo (CPU, memória, uptime, ping, tráfego de rede e armazenamento) pronto para importar em qualquer Grafana com o plugin Zabbix instalado. Ele não tem nenhum host, grupo ou IP fixo — usa variáveis (`$group`, `$host_a`, `$host_b`, `$host_c`) que se adaptam automaticamente ao Zabbix de quem importar. Passo a passo completo de importação e troubleshooting em [`grafana-dashboards/README.md`](./grafana-dashboards/README.md).

## Destaques técnicos / desafios resolvidos

- **Housekeeper do Zabbix** ajustado para reter apenas o necessário,
  evitando crescimento descontrolado do banco em ambientes pequenos
- **Bug conhecido do Zabbix Agent2 no Windows**: `system.uptime` e
  `system.cpu.util` retornam sempre vazio/zero nessa plataforma —
  documentado o workaround via WMI e, na raiz, a correção via rebuild
  do catálogo de Performance Counters do Windows (`lodctr /r`)
- **Hardening de rede real**: política deny-by-default em `ufw`, com
  nota sobre a limitação de filtrar egress por domínio (L3/L4) e como
  resolver isso com um proxy de saída L7
- **Dashboard Grafana totalmente parametrizado** com variáveis do
  plugin Zabbix (`$group`/`$host`), eliminando qualquer host, IP ou
  grupo fixo — reutilizável por qualquer pessoa que importe o JSON
- **MySQL sob pressão de memória**: com `mem_limit` de 512m, o container
  ficava constantemente perto de 100% de uso mesmo com
  `innodb-buffer-pool-size` travado em 256M — o teto não deixava espaço
  pra overhead de conexões/buffers. Sintoma enganoso: falha intermitente
  de login no Zabbix Web parecendo credencial errada. Corrigido subindo
  o limite pra 1g e reduzindo `max-connections` de 100 pra 50
- **Deriva de relógio em VM de laboratório**: `chronyd` detectou até ~5
  dias de atraso após a VM ser pausada/retomada, mas ficou preso em
  correção gradual (*slew*) por já ter passado da janela padrão de
  `makestep` (só permite correção brusca nos primeiros ciclos após o
  boot). Sintoma enganoso: painéis com range de tempo longo (3h+)
  mostravam dado normal, só o range curto (1h) ficava em "No data", e a
  fonte de dados do Grafana chegava a retornar "Unauthorized"
  intermitente. Corrigido com `chronyc makestep` + ajuste permanente em
  `chrony.conf` (script `scripts/fix-vm-clock.sh`)
- **Delay de descoberta automática (LLD) de interface de rede**: os itens
  `Interface eth0: Bits received/sent` não existem logo após cadastrar
  um host — são criados por uma regra de descoberta com intervalo padrão
  de 1h, do tipo "Zabbix agent (active)" (não pode ser forçada via
  "Execute now" no Zabbix Web). Reduzir o "Update interval" da regra
  "Network interface discovery" pra ~10min evita a espera
- **Agent em container medindo a rede errada**: com o agent do Servidor B
  numa rede bridge do Docker, a descoberta só encontrava a `eth0` do
  container, então o tráfego exibido era o do container, não o do
  servidor (e a placa real, ex. `enp3s0`, nunca aparecia). Corrigido com
  `network_mode: host`; o painel passou a aceitar qualquer nome de placa
  física (`eth*`/`en*`) por regex, ignorando `docker0`, `veth*` e `lo`
- **Discos montados invisíveis para o agent**: com `/:/hostfs:ro`, as
  montagens abaixo de `/` (ex. `/dados`) não apareciam dentro do
  container. Corrigido com propagação `rslave` no volume
- **Grafana em loop de restart na primeira subida**: a pasta
  `data/grafana` é criada pelo root, mas o Grafana roda como UID 472.
  Sintoma: `mkdir: can't create directory '/var/lib/grafana/plugins':
  Permission denied`. Corrigido com `chown -R 472:472 data/grafana`
- **Ícone ZBX amarelo em host Windows ativo**: itens do tipo "Zabbix
  agent" (passivo) num host cujo agent só funciona em modo ativo fazem o
  servidor tentar conectar na 10050 e marcar a interface passiva como
  indisponível. Host em modo ativo deve ter só itens "Zabbix agent
  (active)"
- **Painel independente do nome dos itens**: uptime do Windows aceita o
  item padrão `Uptime` ou o workaround `Uptime (WMI)`, e o disco `D:`
  aceita qualquer rótulo de volume

## Status do projeto

- [x] Zabbix Server + Web + Grafana + MySQL (Servidor A)
- [x] Zabbix Agent2 em modo ativo (Servidor B — Linux)
- [x] Zabbix Agent2 em modo ativo (Servidor C — Windows), com
      workarounds para os bugs de CPU/Uptime documentados
- [x] Hardening de firewall (ufw) com política deny-by-default
- [x] Dashboard Grafana parametrizado com variáveis, pronto para reuso
- [ ] Integração de alertas via webhook para automação externa
      (próxima etapa)
