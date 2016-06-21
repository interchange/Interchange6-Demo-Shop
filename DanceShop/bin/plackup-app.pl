#!/bin/bash

CAMPDIR=${PWD%/*}

[[ $CAMPDIR =~ ([[:digit:]]+) ]]
CAMPNUMBER=${BASH_REMATCH[1]}

export PERL5LIB=$CAMPDIR/local/lib/perl5"${PERL5LIB:+:$PERL5LIB}";
export PERL5LIB=$CAMPDIR/local/lib/perl5/x86_64-linux"${PERL5LIB:+:$PERL5LIB}";

PID=$CAMPDIR/var/run/plackup-app.pid
PORT=50$CAMPNUMBER
WORKERS=2
APP_DIR="$CAMPDIR/DanceShop"
APP=$APP_DIR/bin/dev.psgi

plackup="$CAMPDIR/local/bin/plackup"
plackup_args="-E development -o 127.0.0.1 -p $PORT -s Starman --pid=$PID --workers $WORKERS -D"
website="camp $CAMPNUMBER on port $PORT"
lockfile=$CAMPDIR/var/lock/plackup-app

start() {
    [ -x $plackup ] || exit 5
    [ -f $APP ] || exit 6
    echo "Starting $website."
    $plackup $plackup_args -a $APP 2>&1 > /dev/null
    retval=$?
    [ $retval = 0 ] && touch $lockfile
    return $retval
}

stop() {
    echo "Stopping $website."
    if [ -f $PID ]; then
        kill -QUIT `cat $PID` 2>&1> /dev/null
        retval=$?
        [ $retval -eq 0 ] && rm -f $lockfile ${PID}
    fi
}

restart() {
    stop
    start
}

case "$1" in
    start)
        $1
        ;;
    stop)
        $1
        ;;
    restart)
        $1
        ;;
    *)
        echo $"Usage: $0 {start|stop|restart}"
        exit 2
esac

