#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hardening UFW - SERVIDOR A (Zabbix Server + Grafana)
#
# Princípios:
# - Deny-by-default em entrada E saída (whitelist estrita)
# - Só fala com o Servidor B na rede local
# - Não aceita nenhuma conexão vinda da internet
# ============================================================

SERVER_B_IP="${SERVER_B_IP:?defina o IP interno do Servidor B, ex: 10.0.0.11}"
ADMIN_SSH_SOURCE="${ADMIN_SSH_SOURCE:?defina a origem permitida para SSH, ex: 10.0.0.0/24}"

echo "[*] Resetando regras..."
ufw --force reset

echo "[*] Políticas padrão: negar tudo, entrada e saída..."
ufw default deny incoming
ufw default deny outgoing

echo "[*] Permitindo loopback..."
ufw allow in on lo
ufw allow out on lo

echo "[*] SSH restrito à rede de administração..."
ufw allow in from "$ADMIN_SSH_SOURCE" to any port 22 proto tcp

echo "[*] Entrada permitida somente do Servidor B..."
ufw allow in from "$SERVER_B_IP" to any proto icmp
ufw allow in from "$SERVER_B_IP" to any port 10051 proto tcp

echo "[*] Saída DNS e NTP..."
ufw allow out 53 proto udp
ufw allow out 53 proto tcp
ufw allow out 123 proto udp

echo "[*] Saída HTTPS (443) - usado para notificações de alerta..."
ufw allow out 443 proto tcp
# Para restrição estrita por domínio (ufw não filtra por hostname),
# considere um proxy de saída L7 (ex: Squid com ACL de domínio) na frente
# dessa regra.

echo "[*] Habilitando UFW..."
ufw --force enable
ufw status verbose
