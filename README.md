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
└── webhooks/                   # Zabbix/Kuma → n8n (em construção, próxima etapa)
```

## Uso

Em cada servidor:

```bash
cp .env.example .env
# edite o .env com os valores reais do seu ambiente
docker compose up -d
```

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

## Status do projeto

- [x] Zabbix Server + Web + Grafana + MySQL (Servidor A)
- [x] Zabbix Agent2 em modo ativo (Servidor B — Linux)
- [x] Zabbix Agent2 em modo ativo (Servidor C — Windows), com
      workarounds para os bugs de CPU/Uptime documentados
- [x] Hardening de firewall (ufw) com política deny-by-default
- [x] Dashboard Grafana parametrizado com variáveis, pronto para reuso
- [ ] Integração de alertas via webhook para automação externa
      (próxima etapa)
