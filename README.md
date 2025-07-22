# 🛠️ EBPS SQL Backup Tool (GUI)

This PowerShell script launches a WPF GUI that helps authenticated users back up selected SQL databases from remote servers to a network locations. It supports instance detection, backup paths, and interactive selection for SQL servers, databases, and destinations.

---

## 🧩 Features

- GUI built in WPF XAML
- Interactive selection of SQL hosts, instances, and databases
- Remote database backup via `Backup-SqlDatabase`
- Automove of backup files to specified UNC path
- Custom alt path support and status feedback

---

## 🧪 Requirements

- PowerShell 5.1+
- Windows AD credentials
- SQLPS module available on target servers
- Remote PowerShell enabled with CredSSP
- Proper permissions for SQL instance and UNC paths

---

## ⚙️ Configuration Overview

| Variable | Description |
|---------|-------------|
| `$sql_server_list` | Hashtable of SQL server shortnames and hostnames/IPs |
| `$backup_server_list` | Hashtable of backup destinations in UNC format |
| `$local_backupPath` | Temp storage path on the SQL host before transfer |

---

## 🚀 Usage Summary

1. Script prompts for credentials
2. GUI launches with selection menus
3. User selects:
   - SQL host
   - Database(s)
   - Backup destination
4. Upon clicking “Backup,” script triggers a remote connection
5. Backup is performed and moved to destination

> ⚠️ Notes:
> - Target servers must support remote PowerShell and have `sqlps` available  
> - This version assumes a single SQL instance per server  
> - Files are moved after backup, not copied  

---

## ⚠️ Disclaimer

This script was built for internal automation and learning purposes. It reflects real-world infrastructure work and may include assumptions specific to past environments. Please check paths, permissions, and  logic before applying to live systems.