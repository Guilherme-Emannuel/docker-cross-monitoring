#!/bin/bash
# ============================================================
# fix-vm-clock.sh
#
# Corrige desalinhamento de relogio em VMs que sao pausadas/retomadas
# com frequencia (comum em ambientes de laboratorio/VirtualBox/VMware).
#
# Problema: por padrao, o chrony so permite correcao brusca (step) nos
# primeiros ciclos apos o boot do servico (makestep 1 3). Depois disso,
# qualquer desalinhamento cai em correcao gradual (slew), que para uma
# diferenca de horas ou dias pode levar dias inteiros para se ajustar
# sozinho. Isso gera sintomas enganosos: dashboards com range de tempo
# curto (5min, 1h) ficam em "No data" mesmo com tudo funcionando, e a
# fonte de dados do Grafana pode ate retornar "Unauthorized"
# intermitente (sessao/token da API validado com timestamp incorreto).
#
# Uso: sudo ./fix-vm-clock.sh
# ============================================================

set -e

if ! command -v chronyc &> /dev/null; then
    echo "chrony nao encontrado. Este script assume chrony como servico de NTP."
    echo "Se o sistema usar systemd-timesyncd, use:"
    echo "  sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd"
    exit 1
fi

echo "=== Estado atual ==="
chronyc tracking

echo ""
echo "=== Forcando correcao imediata (step) ==="
sudo chronyc makestep

echo ""
echo "=== Tornando a correcao permanente (makestep sem limite de ciclos) ==="
if grep -q "^makestep 1 3" /etc/chrony/chrony.conf; then
    sudo sed -i 's/^makestep 1 3/makestep 1 -1/' /etc/chrony/chrony.conf
    echo "Linha 'makestep' atualizada para permitir step sempre que necessario."
else
    echo "Linha 'makestep 1 3' nao encontrada como esperado — confira manualmente:"
    grep -i makestep /etc/chrony/chrony.conf || echo "(nenhuma diretiva makestep encontrada)"
fi

sudo systemctl restart chrony
sleep 3

echo ""
echo "=== Estado final ==="
chronyc tracking
date
