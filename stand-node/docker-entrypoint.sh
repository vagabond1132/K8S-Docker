#!/usr/bin/env bash
set -Eeo pipefail

export PGDATA=/opt/HighGoDB-4.3.4/data
export PATH=/opt/HighGoDB-4.3.4/bin:$PATH
export HG_BASE=/opt/HighGoDB-4.3.4
export LD_LIBRARY_PATH=/opt/HighGoDB-4.3.4/lib


if [ -f /opt/highgodb-4.3.4-1.ns7.mips64el.rpm ]; then
	rpm -ivh /opt/highgodb-4.3.4-1.ns7.mips64el.rpm
fi



mkdir -p /opt/HighGoDB-4.3.4/conf 

export hostip=`ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d '/'`
export hostname=`hostname`
export node_id=`echo $hostname | tr -cd "[0-9]"`  ##rep02 ==> 02;

#export ethname=`ip addr | grep 'state UP' -A2 | tail -n3  | awk '{print $2}' | cut -f1 -d ':' | head -n 1`

#fc 挂载;;
if [ -d /opt/HighGoDB-4.3.4/data/lost+found ]; then
	rm -rf /opt/HighGoDB-4.3.4/data/lost+found
fi

if [ `ls -ls /opt/HighGoDB-4.3.4/data | wc -l` -le 3 ]; then
   echo "Init hgdb"	
  /opt/HighGoDB-4.3.4/bin/initdb -D /opt/HighGoDB-4.3.4/data --pwfile=/opt/pwfile
  cp /opt/HighGoDB-4.3.4/etc/server.crt /opt/HighGoDB-4.3.4/etc/server.key /opt/HighGoDB-4.3.4/data/
  chmod 600 /opt/HighGoDB-4.3.4/data/server.key
fi

if [ -f /opt/pgpass ]; then
	echo "chmod pgpass perm"
	cp -rf  /opt/pgpass ~/.pgpass
	rm -f /opt/pgpass
	chmod 600 ~/.pgpass
fi


if [  -f /opt/hg_repmgr.conf ]; then
	cp -rf /opt/hg_repmgr.conf /opt/HighGoDB-4.3.4/conf/
	rm -f  /opt/hg_repmgr.conf

###conf配置文件;;
	echo "Set hg_repmgr.conf"
	sed -i 's/node_id=1/node_id='`echo $node_id`'/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
	sed -i 's/node_name="rep1"/node_name="'`hostname`'"/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
	#sed -i 's/conninfo="host=rep1 user=sysdba/conninfo="host='`hostname`' user=sysdba/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
	sed -i 's/conninfo='\''host=rep1 user=sysdba dbname=highgo password=highgo@123/conninfo='\''host='`hostname`' user=sysdba dbname=highgo password=highgo@123/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf

fi


if [ -f /opt/pwfile ]; then
	echo "removing passfile"
	rm -rf /opt/pwfile
fi


if [ -f /opt/highgodb-4.3.4-1.ns7.mips64el.rpm ]; then ## 需要放置到上面?
	echo "Set postgres.conf & pg_hba.conf"
	rm -rf /opt/highgodb-4.3.4-1.ns7.mips64el.rpm
	echo "host    all             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
	echo "hostssl    all             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
	echo "host    replication             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
	echo "hostssl replication             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
	sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g"  /opt/HighGoDB-4.3.4/data/postgresql.conf
	sed -i "s/#wal_log_hints = off/wal_log_hints = on/g" /opt/HighGoDB-4.3.4/data/postgresql.conf
	sed -i "s/#full_page_writes = on/full_page_writes = on/g" /opt/HighGoDB-4.3.4/data/postgresql.conf	
	sed -i "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" /opt/HighGoDB-4.3.4/data/postgresql.conf
	echo "shared_preload_libraries = 'repmgr' " >> /opt/HighGoDB-4.3.4/data/postgresql.conf
	echo "search_path = '\"\$user\", public,esms_base' " >> /opt/HighGoDB-4.3.4/data/postgresql.conf
fi

/opt/HighGoDB-4.3.4/bin/pg_ctl -D /opt/HighGoDB-4.3.4/data -w start

if [[ ! -f /opt/HighGoDB-4.3.4/data/.init  ||  `cat /opt/HighGoDB-4.3.4/data/.init` != "init" ]]; then
	echo "pg_restart oper"

	psql=( psql -v ON_ERROR_STOP=1 --username "sysdba" --no-password )
	psql+=( --dbname "highgo" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)
					# https://github.com/docker-library/highgo/issues/450#issuecomment-393167936
					# https://github.com/docker-library/highgo/pull/452
					if [ -x "$f" ]; then
						echo "$0: running $f"
						"$f"
					else
						echo "$0: sourcing $f"
						. "$f"
					fi
					;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" -f "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done
	
	if [ -f /opt/esms_base.sql ]; then
		rm -rf /docker-entrypoint-initdb.d/create-database.sh
		#rm -rf /docker-entrypoint-initdb.d/oa20190416pm.backup
		rm -rf /opt/esms_base.sql
	fi

echo "init" > /opt/HighGoDB-4.3.4/data/.init

unset PGPASSWORD
unset hostip
unset hostname
unset node_id

echo 
echo 'HighGo init process complete; ready for start up.'
echo


fi
