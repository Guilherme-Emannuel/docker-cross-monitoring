# Servidor C — Zabbix Agent2 no Windows

Diferente dos servidores A e B (Linux, via Docker), este host roda o Zabbix
Agent2 nativamente, como serviço do Windows — evitando o overhead de
Docker Desktop numa máquina que também hospeda dados de produção.

## 1. Download e verificação de integridade

Baixe o instalador oficial (`Zabbix agent 2`, MSI, versão compatível com o
Zabbix Server) em https://www.zabbix.com/download_agents

Antes de instalar, confira o checksum SHA256 publicado na página contra o
arquivo baixado:

```powershell
Get-FileHash "C:\caminho\zabbix_agent2-X.Y.Z-windows-amd64-openssl.msi" -Algorithm SHA256
```

## 2. Instalação silenciosa, já em modo ativo

Modo ativo = o agent inicia a conexão para o Zabbix Server (saída), nunca
o contrário — não é necessário abrir nenhuma porta de entrada no host.

```powershell
Start-Process msiexec.exe -ArgumentList '/i "C:\caminho\zabbix_agent2-X.Y.Z-windows-amd64-openssl.msi" SERVER=<IP_DO_SERVIDOR_A> SERVERACTIVE=<IP_DO_SERVIDOR_A>:10051 HOSTNAME="Servidor C" ENABLEPATH=1 /qn /l*v "C:\zabbix_install.log"' -Wait
```

## 3. Hardening — bloquear execução de comandos remotos

Especialmente relevante numa máquina com dados sensíveis: o Zabbix Server
não deve conseguir mandar o agent executar comandos no sistema.

No `zabbix_agent2.conf`, adicione:
```
DenyKey=system.run[*]
```

(a diretiva antiga `EnableRemoteCommands` não existe mais no Agent2 —
usar `DenyKey` sozinho já bloqueia essa via)

## 4. Validar a configuração antes de iniciar o serviço

```powershell
& "C:\Program Files\Zabbix Agent 2\zabbix_agent2.exe" -c "C:\Program Files\Zabbix Agent 2\zabbix_agent2.conf" -T
Start-Service "Zabbix Agent 2"
```

## 5. Confirmar que nenhuma porta de entrada ficou aberta

```powershell
Get-NetFirewallRule -DisplayName "*Zabbix*"
```
Em modo ativo, não deve existir nenhuma regra de **entrada** liberando a
porta 10050 — se existir, remova.

## Bug conhecido: itens nativos retornando 0 / erro em Windows

O Zabbix Agent2 tem bugs documentados no Windows onde `system.uptime` e
`system.cpu.util` retornam sempre vazio/zero — não é erro de configuração.
Workaround: itens customizados via WMI, que não dependem dos Performance
Counters problemáticos:

- **Uptime**: `wmi.get[root\cimv2,"select LastBootUpTime from Win32_OperatingSystem"]`
  (requer pré-processamento para converter a data de boot em segundos de uptime)
- **CPU utilization**: `wmi.get[root\cimv2,"select LoadPercentage from Win32_Processor"]`

Se os Performance Counters do Windows estiverem corrompidos de forma mais
ampla (sintoma: `Get-Counter -ListSet "Processor"` retorna vazio), a causa
raiz se corrige com:
```powershell
lodctr /r
net stop winmgmt /y
net start winmgmt
```
⚠️ Isso reinicia o serviço WMI, o que interrompe temporariamente qualquer
outro software dependente de WMI (ex: alguns antivírus, backups via VSS,
ferramentas de acesso remoto como Tailscale). Confirme que nenhum backup
está em andamento antes de rodar, e tenha um plano para restabelecer
manualmente serviços que dependam do WMI, caso não voltem sozinhos.
