#!/usr/bin/env bash
# 模块：节点搭建（Sing-box / Xray / Hysteria2 / Tuic 等脚本入口）

sst_register_module nodes "节点搭建" "Sing-box Xray Hysteria2 Tuic 等"
SST_MODULE_ITEMS[nodes]=$'list|全部节点脚本\nsingbox|F佬 Sing-box\nsingbox-233boy|233boy Sing-box\nsingbox-yg|勇哥 Sing-box\nhysteria2|Hysteria2\ntuic|Tuic v5\njuicity|Juicity\nreality|Xray Reality\nxray2go|Xray-2go\nxui|X-UI\n3xui|3X-UI\nsui|S-UI 面板\nargox|ArgoX\nsuoha|Suoha Argo\nopenvpn|OpenVPN\ntgproxy|TG 代理'

nodes_list() { scripts_menu 节点; }
