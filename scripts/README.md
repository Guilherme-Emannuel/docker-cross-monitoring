# scripts/

Scripts utilitários reutilizáveis entre os três servidores do projeto.

## fix-vm-clock.sh

Corrige e torna permanente a sincronização de relógio em VMs Linux que usam **chrony** como serviço de NTP.

### Por que existe

Em ambientes de laboratório (VirtualBox, VMware, VMs que são pausadas/retomadas com frequência), o relógio do sistema pode ficar horas ou até dias atrasado depois de a VM voltar de uma pausa. O `chronyd` detecta essa diferença, mas por padrão só corrige de forma **brusca (step)** durante os primeiros ciclos após o início do serviço (`makestep 1 3` — 3 ciclos). Depois disso, qualquer desalinhamento cai em correção **gradual (slew)**, que para uma diferença grande (horas/dias) pode levar dias inteiros pra se ajustar sozinha.

### Sintomas que esse problema causa

- Dashboards do Grafana (ou qualquer ferramenta que consulte dados por intervalo de tempo) mostram dado normalmente em ranges longos (3h, 24h), mas ficam em **"No data"** em ranges curtos (5min, 1h) — porque os dados coletados têm timestamp desalinhado em relação ao "agora" real.
- Fontes de dados (ex: plugin Zabbix do Grafana) podem retornar erro **"Unauthorized"** de forma intermitente — suspeita: validação de sessão/token da API usando timestamp incorreto.
- Nenhum desses sintomas aponta obviamente pra "relógio errado" — parece problema de permissão, conexão ou configuração, o que torna esse diagnóstico difícil de achar na prática.

### O que o script faz

1. Confirma que o `chrony` está instalado e mostra o estado atual (`chronyc tracking`).
2. Força uma correção imediata do relógio (`chronyc makestep`).
3. Edita `/etc/chrony/chrony.conf`, trocando `makestep 1 3` por `makestep 1 -1` — isso remove o limite de ciclos, permitindo correção brusca **sempre** que necessário, não só logo após o boot.
4. Reinicia o serviço `chrony` e mostra o estado final, já corrigido.

### Uso

```bash
chmod +x scripts/fix-vm-clock.sh
sudo ./scripts/fix-vm-clock.sh
```

Se o sistema usar `systemd-timesyncd` em vez de `chrony`, o script avisa e não faz nada — nesse caso, o equivalente manual é:

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
timedatectl status   # confirme "System clock synchronized: yes"
```

### Quando rodar

- Uma vez, logo depois de qualquer VM nova ser criada (antes de subir os containers).
- Sempre que a VM for pausada/hibernada e retomada e você notar dado "sumindo" em ranges curtos do Grafana sem motivo aparente.
