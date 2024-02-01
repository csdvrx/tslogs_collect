#!/bin/sh
# Copyright (C) 2024, csdvrx, MIT licensed

# Assumptions:
#  - runs binaries:  sqlite3, date, sysctl, mv, echo
#  - writable file:  ${1} (or /tslogs.sqlite by default)
#  - creates files:  ${2} (or /tmp by default)

#debug
#echo "1: ${1}, 2:${2}"

# Use an optional filename, or /tslogs.sqlite by default
[ -n "${1}" ] \
 && TSLOGS_FILE="${1}" \
 || TSLOGS_FILE="/tslogs.sqlite"

# Use an optional path, like /var/tmp, or /tmp by default
[ -n "${2}" ] \
 && [ -d "${2}" ] \
 && TEMP_PATH="${2}"

# If we don't have /tmp, we need a place to store the logs
[ -z "${2}" ] \
 && TEMP_PATH="/tmp"

# Collect boot variables by forking more processes:
# Ugly/slow/wrong because it adds parasite entries the userland tslogs
# Enough to get started as a PoC but TODO: syscalls in C from within bslinit
# WONTFIX: could try to pipe directly to sqlite3 .import to avoid /tmp files
# But what if the tables do not exist?
# A first sqlite (CREATE TABLE IF NOT EXISTS...) would parasite tslog_user

# Until a C rewrite, collect the userland tslog first to limit parasite pids
sysctl -b debug.tslog_user > "${TEMP_PATH}"/tslog_userlp.txt

# The kernel tslog can be done next
sysctl -b debug.tslog > "${TEMP_PATH}"/tslog_kernel.txt

# Then get the variables
MACHINE=$( sysctl -n hw.machine        )
   ARCH=$( sysctl -n hw.machine_arch   )
     OS=$( sysctl -n kern.ostype       )
  BTIME=$( sysctl -n kern.boottime     )
  KCONF=$( sysctl -n kern.configname   )
  CLOCK=$( sysctl -n kern.clockrate    )
   FREQ=$( sysctl -n machdep.tsc_freq  )
    CPU=$( sysctl -n machdep.cpu_brand )
# WARNING: version is multiline
VERSION=$( sysctl -n kern.version      )

#debug:
#echo "Storing into ${TSLOGS_FILE} data temporarily extracted to ${TEMP_PATH}"
#echo "Got machine: '${MACHINE}', arch: '${ARCH}', os: '${OS}', btime: '${BTIME}', kconf: '${KCONF}', clock: '${CLOCK}', freq: '${FREQ}', cpu: '${CPU}', version: '${VERSION}'"

# Schemas: hopefully enough to allow comparisons between netbsd and freebsd and between arch
# From https://github.com/cperciva/freebsd-boot-profiling:
# aarch64 needs sysctl -n "kern.timecounter.tc.ARM MPCore Timecounter.frequency"
# variables are read like `sysctl -n machdep.tsc_freq`
STORE_BOOT="BEGIN TRANSACTION;
 CREATE TABLE IF NOT EXISTS boots (                     -- table of boots
  bid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,       -- primary key
  added TIMESTAMP NOT NULL DEFAULT current_timestamp,   -- rough estimation of btime in native TS format
  machine TEXT,                                         -- hw.machine: amd64
  arch    TEXT,                                         -- hw.machine_arch: x86_64
  os      TEXT,                                         -- kern.ostype: NetBSD
  btime   TEXT,                                         -- kern.boottime: Thu Feb  1 15:09:59 2024
  kconf   TEXT,                                         -- kern.configname: MICROVM
  clock   TEXT,                                         -- kern.clockrate: tick = 10000, tickadj = 40, hz = 100, profhz = 100, stathz = 100
  freq    TEXT,                                         -- machdep.tsc_freq: 2496000000
  cpu     TEXT,                                         -- machdep.cpu_brand: 12th Gen Intel(R) Core(TM) i7-1270P
  version TEXT                                          -- kern.version: (very long) TODO: extract details
 ); 
CREATE TABLE IF NOT EXISTS kernel  (                    -- table of tslog kernel functions
  kid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,       -- primary key
  fk_k_bid INTEGER,                                    -- foreign primary key bid
  approx TIMESTAMP NOT NULL DEFAULT current_timestamp,  -- when too lazy to join boot to get and convert btime
  phase TEXT,                                           -- hexadecimal number, TODO: add decimal printf variable
  epoch INTEGER,                                        -- seconds, TODO: add converted timestamp
  type TEXT,                                            -- TODO: could be an enum: ENTER,THREAD,EXIT
  event TEXT,                                           -- kernel event
  detail TEXT DEFAULT NULL,                             -- extra, optional
  FOREIGN KEY (fk_k_bid) REFERENCES boots(bid)         -- link to boots
 );
CREATE TABLE IF NOT EXISTS temp_tslk (                  -- temp for raw imports
  phase TEXT,                                           -- hexadecimal number, TODO: add decimal printf variable
  epoch INTEGER,                                        -- seconds, TODO: add converted timestamp
  type TEXT,                                            -- TODO: could be an enum: ENTER,THREAD,EXIT
  event TEXT,                                           -- kernel event
  detail TEXT DEFAULT NULL                              -- extra, optional
);
CREATE TABLE IF NOT EXISTS userlp (                     -- table of tslog userland processes
  tid INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,       -- primary key
  fk_u_bid INTEGER,                                    -- foreign primary key bid
  past TIMESTAMP NOT NULL DEFAULT current_timestamp,    -- when too lazy to join boot to get and convert btime
  pid INTEGER,                                          -- process id
  ppid INTEGER,                                         -- parent id
  start INTEGER,                                        -- pid start epoch, TODO: add converted ts
  stops INTEGER,                                        -- pid stop epoch, 0 if still runninng, TODO: same
  what TEXT,                                            -- full path of what was running
  smtg TEXT DEFAULT NULL,                               -- TODO: wtf is it? always seems null
  FOREIGN KEY (fk_u_bid) REFERENCES boots(bid)         -- link to boots
 );
CREATE TABLE IF NOT EXISTS temp_tslu (                  -- temp for raw imports
  pid INTEGER,                                          -- process id
  ppid INTEGER,                                         -- parent id
  start INTEGER,                                        -- pid start epoch, TODO: add converted ts
  stops INTEGER,                                        -- pid stop epoch, 0 if still runninng, TODO: same
  what TEXT,                                            -- full path of what was running
  smtg TEXT DEFAULT NULL                                -- TODO: wtf is it? always seems null
);
--INSERT OR IGNORE INTO boots (bid,"0");                  -- can be used to satisfy fk constraint until updated with BID
INSERT INTO boots (machine, arch, os, btime, kconf, clock, freq, cpu, version) VALUES (
 '${MACHINE}',
 '${ARCH}',
 '${OS}',
 '${BTIME}',
 '${KCONF}',
 '${CLOCK}',
 '${FREQ}',
 '${CPU}',
 '${VERSION}'
);
SELECT max(bid) from boots;
COMMIT;"

#debug:
#echo "Running sqlite3 \"${TSLOGS_FILE}\" \"${STORE_BOOT}\" to obtain BID"

# Store the boot first
BID=$( <. sqlite3 "${TSLOGS_FILE}" "${STORE_BOOT}" )

#debug:
#echo "New pk fk for the tslogs: boot id:${BID}"

# Then store the tslogs themselves:
# In case we want to persist them (ie if the temporary path is not so temporary)
NOW=$( date +%Y%m%d%H%M%S )

# .import may complain like:
# expected 5 columns but found 1 - filling the rest with NULL
# so just disable its stderr with '2>/dev/null'

[ -f "${TEMP_PATH}/tslog_kernel.txt" ] \
 && sqlite3 -separator ' ' "${TSLOGS_FILE}" ".import "${TEMP_PATH}/tslog_kernel.txt" temp_tslk" 2>/dev/null \
 && echo "Imported into ${TSLOGS_FILE} temp_tslk table the data from ${TEMP_PATH}/tslog_kernel.txt" \
 && mv "${TEMP_PATH}/tslog_kernel.txt" "${TEMP_PATH}/tslog_kernel_$NOW.txt" \
 || echo "Problem with temp_tslk import or backup of ${TEMP_PATH}/tslog_kernel.txt to ${TEMP_PATH}/tslog_kernel_$NOW.txt"

[ -f "${TEMP_PATH}/tslog_userlp.txt" ] \
 && sqlite3 -separator ' ' "${TSLOGS_FILE}" ".import "${TEMP_PATH}/tslog_userlp.txt" temp_tslu" 2>/dev/null \
 && echo "Imported into ${TSLOGS_FILE} temp_tslu table the data from ${TEMP_PATH}/tslog_userlp.txt" \
 && mv "${TEMP_PATH}/tslog_userlp.txt" "${TEMP_PATH}/tslog_userlp_$NOW.txt" \
 || echo "Problem with temp_tslu import or backup of ${TEMP_PATH}/tslog_userlp.txt to ${TEMP_PATH}/tslog_userlp_$NOW.txt"

# Can now import from the temp tables into kernel and userlp with the pk BID
# the 1st column can be NULL or "" (2 different things in sql...)

UPDATE_TEMP="BEGIN TRANSACTION;
INSERT INTO kernel (fk_k_bid, phase, epoch, type, event, detail)
SELECT (SELECT MAX(boots.bid) FROM boots), temp_tslk.phase, temp_tslk.epoch, temp_tslk.type, temp_tslk.event, temp_tslk.detail
FROM temp_tslk WHERE temp_tslk.phase IS NOT NULL AND temp_tslk.phase<>'';
DELETE FROM temp_tslk; -- flush
COMMIT;
BEGIN TRANSACTION;
INSERT INTO userlp (fk_u_bid, pid, ppid, start, stops, what)
SELECT (SELECT MAX(boots.bid) FROM boots),
 temp_tslu.pid, temp_tslu.ppid, temp_tslu.start, temp_tslu.stops, temp_tslu.what
FROM temp_tslu WHERE temp_tslu.pid IS NOT NULL AND temp_tslu.pid<>'';
DELETE FROM temp_tslu; -- flush
COMMIT;
-- check
SELECT (SELECT COUNT(*) FROM temp_tslu) + (SELECT COUNT(*) FROM temp_tslk);
"
# Store the boot first
LEFTOVERS=$( <. sqlite3 "${TSLOGS_FILE}" "${UPDATE_TEMP}" )

echo "Update tables, left over ${LEFTOVERS} should be null"

# TODO: write a separate script to create the svg files by rewriting in pure perl
# https://github.com/cperciva/freebsd-boot-profiling/blob/master/mkflame.sh
