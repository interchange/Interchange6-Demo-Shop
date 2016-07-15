use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More;
use Test::Warnings;
use Test::WWW::Mechanize::PSGI;

use DanceShop;

my $app = DanceShop->to_app;

my $mech = Test::WWW::Mechanize::PSGI->new( app => $app );

$mech->get_ok( '/trim-brush', "GET /trim-brush (product route via uri)" );

$mech->content_like( qr|<p class="short-description">Trim Brush</p>|, 'found Trim Brush' )
    or diag $mech->content;

$mech->get_ok( '/os28005', "GET /os28005 (product route via sku)" );

done_testing;
