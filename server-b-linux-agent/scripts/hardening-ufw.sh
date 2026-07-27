#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Hardening UFW - SERVIDOR B (Zabbix Agent ativo)
# Mesmos princípios do Servidor A, espelhado.
# ============================================================

SERVER_A_IP="${SERVER_A_IP:?defina o IP interno do Servidor A, ex: 10.0.0.10}"
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

echo "[*] Entrada permitida somente do Servidor A..."
ufw allow in from "$SERVER_A_IP" to any proto icmp

echo "[*] Saída para o Servidor A (agent ativo empurra métricas)..."
ufw allow out to "$SERVER_A_IP" port 10051 proto tcp
ufw allow out to "$SERVER_A_IP" proto icmp

echo "[*] Saída DNS e NTP..."
ufw allow out 53 proto udp
ufw allow out 53 proto tcp
ufw allow out 123 proto udp

echo "[*] Habilitando UFW..."
ufw --force enable
ufw status verbose
