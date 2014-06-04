package DanceShop;

use Dancer ':syntax';
use Dancer::Plugin::Auth::Extensible;
use Dancer::Plugin::DBIC;
use Dancer::Plugin::Interchange6;
use Dancer::Plugin::Interchange6::Routes;

our $VERSION = '0.0001';

set session => 'DBIC';
set session_options => {schema => schema};

get '/' => sub {
    template 'index';
};

true;
