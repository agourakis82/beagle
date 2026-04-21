#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-kubeconfig.sh"
NS="${NS:-slurm-pilot}"
export KUBECONFIG="${KUBECONFIG_PATH}"

LOGIN_TARGET="deploy/slurm-pilot-login-slinky"

if ! kubectl -n "${NS}" get "${LOGIN_TARGET}" >/dev/null 2>&1; then
  echo "could not find ${LOGIN_TARGET} in namespace ${NS}" >&2
  exit 1
fi

kubectl -n "${NS}" exec "${LOGIN_TARGET}" -- bash -lc '
  set -euo pipefail

  ensure_qos() {
    local name="$1"
    local priority="$2"
    local max_jobs="$3"
    local max_tres="$4"
    local grp_tres="${5:-}"

    if ! sacctmgr -nP list qos format=Name | cut -d"|" -f1 | grep -qx "${name}"; then
      if [[ -n "${grp_tres}" ]]; then
        sacctmgr -i add qos "${name}" Priority="${priority}" MaxJobsPU="${max_jobs}" MaxTRESPerUser="${max_tres}" GrpTRES="${grp_tres}" Flags=DenyOnLimit
      else
        sacctmgr -i add qos "${name}" Priority="${priority}" MaxJobsPU="${max_jobs}" MaxTRESPerUser="${max_tres}" Flags=DenyOnLimit
      fi
    fi
  }

  ensure_account() {
    local name="$1"
    local parent="$2"
    local descr="$3"

    if ! sacctmgr -nP list account format=Account | cut -d"|" -f1 | grep -qx "${name}"; then
      if [[ -n "${parent}" ]]; then
        sacctmgr -i add account "${name}" Parent="${parent}" Description="${descr}" Organization="sounio"
      else
        sacctmgr -i add account "${name}" Description="${descr}" Organization="sounio"
      fi
    fi
  }

  ensure_qos normal 50 8 "cpu=32,mem=128G"
  ensure_qos burst 300 1 "cpu=16,gres/gpu=1,mem=64G" "gres/gpu=2"
  ensure_qos long 25 2 "cpu=16,mem=64G"
  ensure_qos cpuops 100 4 "cpu=16,mem=64G"
  ensure_qos gpuorangefs 200 2 "gres/gpu=1,cpu=16,mem=64G" "gres/gpu=2"

  sacctmgr -i modify qos where Name=normal set Priority=50
  sacctmgr -i modify qos where Name=burst set Priority=300 MaxJobsPU=1 MaxTRESPerUser=cpu=16,gres/gpu=1,mem=64G GrpTRES=gres/gpu=2 Flags=DenyOnLimit
  sacctmgr -i modify qos where Name=long set Priority=25 MaxJobsPU=2 MaxTRESPerUser=cpu=16,mem=64G Flags=DenyOnLimit
  sacctmgr -i modify qos where Name=cpuops set Priority=100 MaxJobsPU=4 MaxTRESPerUser=cpu=16,mem=64G Flags=DenyOnLimit
  sacctmgr -i modify qos where Name=gpuorangefs set Priority=200 MaxJobsPU=2 MaxTRESPerUser=cpu=16,gres/gpu=1,mem=64G GrpTRES=gres/gpu=2 Flags=DenyOnLimit

  ensure_account lab "" "supercomputing lab umbrella account"
  ensure_account pbpk lab "PBPK workloads"
  ensure_account omics lab "Omics preprocessing and analysis"
  ensure_account plruntime lab "Programming language runtime experiments"

  ensure_assoc() {
    local account="$1"
    if ! sacctmgr -nP list assoc format=User,Account | grep -qx "root|${account}"; then
      sacctmgr -i add user root Account="${account}"
    fi
  }

  if ! sacctmgr -nP list user format=User | cut -d"|" -f1 | grep -qx root; then
    sacctmgr -i add user root Account=lab AdminLevel=Administrator
  fi

  ensure_assoc lab
  ensure_assoc pbpk
  ensure_assoc omics
  ensure_assoc plruntime

  sacctmgr -i modify user where Name=root set DefaultAccount=lab

  sacctmgr -i modify account where Name=lab set QOS+=normal DefaultQOS=normal
  sacctmgr -i modify account where Name=pbpk set QOS+=cpuops,long,normal DefaultQOS=cpuops
  sacctmgr -i modify account where Name=omics set QOS+=cpuops,long,normal DefaultQOS=cpuops
  sacctmgr -i modify account where Name=plruntime set QOS+=gpuorangefs,burst,normal DefaultQOS=gpuorangefs

  echo "---QOS---"
  sacctmgr list qos format=Name,Priority,MaxJobsPU,GrpTRES,MaxTRESPerUser,Flags
  echo "---ACCOUNTS---"
  sacctmgr list account format=Account,ParentName,Descr,Organization,Fairshare,QOS,DefaultQOS
  echo "---USERS---"
  sacctmgr list user format=User,DefaultAccount,Account,AdminLevel,QOS,DefaultQOS
'
