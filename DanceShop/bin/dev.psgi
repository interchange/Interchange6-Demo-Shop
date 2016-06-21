#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Plack::Builder;

use DanceShop;
use DBICx::Sugar qw/schema/;
use Dancer2::Debugger;
use Plack::Middleware::DBIC::QueryLog;

my $mw = sub {
    my $app = shift;
    sub {
        my $env = shift;
        my $querylog =
          Plack::Middleware::DBIC::QueryLog->get_querylog_from_env($env);
        my $cloned_schema = schema->clone;
        $cloned_schema->storage->debug(1);
        $cloned_schema->storage->debugobj($querylog);
        $app->($env);
    };
};

my $app = $mw->( DanceShop->to_app );

my $debugger = Dancer2::Debugger->new(
    data_dir => 'plack_debugger'
);

builder {
    enable 'DBIC::QueryLog';
    $debugger->mount;
    mount '/' => builder {
        $debugger->enable;
        $app;
    }
};
