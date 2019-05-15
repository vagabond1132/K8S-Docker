#!/usr/bin/env bash
#set -Eeo pipefail

export PGDATA=/opt/HighGoDB-4.3.4/data
export PATH=/opt/HighGoDB-4.3.4/bin:$PATH
export HG_BASE=/opt/HighGoDB-4.3.4
export LD_LIBRARY_PATH=/opt/HighGoDB-4.3.4/lib

## 勿删. repmgr clone 需要使用;;
#export PGPASSWORD=highgo@123
ClusterName=inspur-highgo

# 计算所需参数;;
#export hostip=`ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d '/'`
export hostname=`hostname`
export node_id=`echo $hostname | tr -cd "[0-9]"`  ##rep02 ==> 02;
#export ethname=`ip addr | grep 'state UP' -A2 | tail -n3  | awk '{print $2}' | cut -f1 -d ':' | head -n 1`


err_exit() {
    
    if [ $? -ne "0" ]; then

        echo "$1 Startup Fail, Err Exit"
        exit 1;
    fi
}


if [ -z $PGPASSWORD ]; then 
    export PGPASSWORD=highgo@123

    > /opt/pwfile
    ## 由k8s 进行传输密码;;;
    n=0
    while [ $n -lt 6 ]
    do
        echo "$PGPASSWORD" >> /opt/pwfile
        n=$(( $n + 1 ))
    done
fi


## 补全Search domain;;
echo "search `tail -n1 /etc/hosts | gawk '{print $2}'  | cut -d '.' -f 2-`" >> /etc/resolv.conf

## 安装HigoGo RPM;;
if [ -f /opt/highgodb-4.3.4-1.ns7.mips64el.rpm ]; then
    rpm -ivh /opt/highgodb-4.3.4-1.ns7.mips64el.rpm
    rm -rf /opt/highgodb-4.3.4-1.ns7.mips64el.rpm
fi

## 校验是否缺失conf;
if [ ! -d /opt/HighGoDB-4.3.4/conf ]; then
    mkdir -p /opt/HighGoDB-4.3.4/conf
fi

#fc 挂载;; -- 外置磁盘;;
if [ -d /opt/HighGoDB-4.3.4/data/lost+found ]; then
    rm -rf /opt/HighGoDB-4.3.4/data/lost+found
fi


if [[ ! -f /opt/HighGoDB-4.3.4/data/.init  || `cat /opt/HighGoDB-4.3.4/data/.init` != "init" ]]; then 
    echo "Init HighGoDB"


    ## initdb;
    /opt/HighGoDB-4.3.4/bin/initdb -D /opt/HighGoDB-4.3.4/data --pwfile=/opt/pwfile
    
    echo "Change postgres.conf && pg_hba.conf"

    ### pg_hba.conf
    echo "host    all             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
    echo "hostssl    all             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
    echo "host    replication             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf
    echo "hostssl replication             all             0.0.0.0/0            md5" >> /opt/HighGoDB-4.3.4/data/pg_hba.conf

    ### postgresql.conf
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g"  /opt/HighGoDB-4.3.4/data/postgresql.conf
    sed -i "s/#wal_log_hints = off/wal_log_hints = on/g" /opt/HighGoDB-4.3.4/data/postgresql.conf
    sed -i "s/#full_page_writes = on/full_page_writes = on/g" /opt/HighGoDB-4.3.4/data/postgresql.conf
    sed -i "s/#wal_keep_segments = 0/wal_keep_segments = 32/g" /opt/HighGoDB-4.3.4/data/postgresql.conf
    echo "shared_preload_libraries = 'repmgr' " >> /opt/HighGoDB-4.3.4/data/postgresql.conf

    ## 拷贝Server key;
    cp /opt/HighGoDB-4.3.4/etc/server.crt /opt/HighGoDB-4.3.4/etc/server.key /opt/HighGoDB-4.3.4/data/

    ## 重新赋值权限;;
    chmod 600 /opt/HighGoDB-4.3.4/data/server.key

    ## 此后即可启动 HiGhGoDB;
fi

## 删除默认的初始化密码文件;;
if [ -f /opt/pwfile ]; then
    echo "Remove HiGhGoDB Passwd File"
    rm -rf /opt/pwfile
fi


## 添加HiGhGoDB 的默认密码文件;
echo > ~/.pgpass
n=0
while [ $n -lt $RepNum ]
do
    echo "$ClusterName-$n:5866:highgo:sysdba:$PGPASSWORD" >> ~/.pgpass   
    n=$(( $n + 1 ))
done
chmod 600 ~/.pgpass  ## 权限赋值;

## repmgr 配置文件;;
if [  -f /opt/hg_repmgr.conf ]; then
    cp -rf /opt/hg_repmgr.conf /opt/HighGoDB-4.3.4/conf/
    rm -f  /opt/hg_repmgr.conf

    ###repmgr conf配置文件;;
    echo "Change HiGhGODB Repmgr Conf File"

    sed -i 's/node_id=1/node_id='1`echo $node_id`'/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
    sed -i 's/node_name="rep1"/node_name="'`hostname`'"/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
    sed -i 's/conninfo='\''host=rep1 user=sysdba dbname=highgo password=highgo@123/conninfo='\''host='`hostname`' user=sysdba dbname=highgo password=highgo@123/g' /opt/HighGoDB-4.3.4/conf/hg_repmgr.conf
fi


/opt/HighGoDB-4.3.4/bin/pg_ctl -D /opt/HighGoDB-4.3.4/data -w start

### 确认当前应该的primary node;;;
declare primary=$REP_MASTER_HOSTNAME  ## 所有节点都未启动; 强设 node-0 为primary node;;
n=0
while [ $n -lt $RepNum ]
do
    if [ $ClusterName-$n != $HOSTNAME ]; then  ### ?? 查询自己??? --- 外置磁盘的时候,允许查询;
	
        echo $PGPASSWORD | psql -U sysdba -d highgo -h $ClusterName-$n -c "select node_name from repmgr.nodes where active='t' and type='primary'" 
	
        if [ "$?" = "0" ]; then 
            primary=`echo $PGPASSWORD | psql -U sysdba -d highgo -h $ClusterName-$n -c "select node_name from repmgr.nodes where active='t' and type='primary'" | sed -n '3p' | cut -d '"' -f2`
            break
	    else 
	        primary=$REP_MASTER_HOSTNAME  ## 所有节点都未启动; 强设 node-0 为primary node;;
        fi
        #break
    fi
    n=$(( $n + 1 ))
done

###防止异常;;;
if [ -z $primary ];then
	primary=$REP_MASTER_HOSTNAME 
fi

echo "Current Primary Node  $primary "
echo "Current Node  $HOSTNAME"

### 校验是否存在外置磁盘;;

####  不存在.init 应该需要重新初始化..  .init != init 也应该重新删除 data, 进行初始化;; ===> initdb 与 pg_restore; --- #仅限于primary node;;
if [[ ! -f /opt/HighGoDB-4.3.4/data/.init  || `cat /opt/HighGoDB-4.3.4/data/.init` != "init" ]]; then

    echo "CONTAINER UnMount Disk"

    if [ $primary = `hostname | cut -f1 -d '.'` ]; then
    #if [ $primary =  `hostname | cut -f1 -d '.'` -a  $primary = $REP_MASTER_HOSTNAME ] ; then

        echo "Primary Register"
        repmgr -F  primary register

        echo "Repmgrd Process Start Up."
        repmgrd -d

        err_exit  repmgrd

        echo "HiGhGoDB Restore"
        psql=( psql -v ON_ERROR_STOP=1 --username "sysdba" --no-password )
        psql+=( --dbname "highgo" )

        echo
        for f in /docker-entrypoint-initdb.d/*; do
            case "$f" in
                *.sh)
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

        if [ -f /docker-entrypoint-initdb.d/oa20190416pm.backup ]; then
            #rm -rf /create-database.sh  ## 删除link
            rm -rf /docker-entrypoint-initdb.d/create-database.sh  ## 存在ln;; 先删除link;
            rm -rf /docker-entrypoint-initdb.d/oa20190416pm.backup
        fi

    else  ### hostname != node-0

        pg_ctl stop
        
        echo "Remove HiGhGoDB Data "
        rm -rf /opt/HighGoDB-4.3.4/data/*

        if [ -f /opt/HighGoDB-4.3.4/data/.init ]; then
            rm -rf /opt/HighGoDB-4.3.4/data/.init
        fi

        echo "Standby Clone"
        repmgr -h $primary -U sysdba -d highgo standby clone

        cp -f  /opt/recovery.conf /opt/HighGoDB-4.3.4/data
        sed -i 's/^primary_conninfo = '\''host=inspur-highgo-0/primary_conninfo = '\''host='`echo $primary`'/g'  /opt/HighGoDB-4.3.4/data/recovery.conf

        pg_ctl start

        echo "Standby Register"
        repmgr -F standby register

        echo "Repmgrd Process Start Up."
        repmgrd -d

        err_exit repmgrd

    fi

    echo
    echo 'HighGo init process complete; ready for start up.'
    echo

else  ## 存在init,, 说明是已经initdb 并且 外挂的磁盘;;
    echo "CONTAINER Mount Disk"
	
	if [ $primary = `hostname | cut -f1 -d '.'` ]; then
	
		echo "Standby Register"
		repmgrd -d 

        err_exit  repmgrd
	
	else
		echo "Standby Register"
		repmgrd -d
       
        err_exit repmgrd
		
		echo "HiGhGODB Shutdown"
		pg_ctl stop
	fi
	
    echo
    echo "HighGoDB Started"
    echo
fi


## 取消变量声明;;;
unset primary
unset hostip
unset hostname
unset node_id


### 生成 .init 文件;; 标志数据库完整 配置;;;
echo "init" > /opt/HighGoDB-4.3.4/data/.init  

### 删除recovery.conf;;
if [ -f /opt/recovery.conf ]; then
    rm -rf  /opt/recovery.conf
fi

exec "$@"  ## 执行特殊用户执行操作;;;
