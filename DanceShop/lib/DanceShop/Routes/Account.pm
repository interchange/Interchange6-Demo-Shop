package DanceShop::Routes::Account;

use strict;
use warnings;

use Dancer2 appname => 'DanceShop';
use Dancer2::Plugin::Auth::Extensible;
use Dancer2::Plugin::Interchange6;


get '/login' => sub {
    my $tokens = {};

    # DPIC6 uses session return_url in post /login
    if ( param('return_url') ) {
        session return_url =>  param('return_url');
    }

    if ( param( 'login_failed' )) {

        # var added by DPAE's post /login route
        $tokens->{login_input} = "has-error";
        $tokens->{login_error} = "Username or password incorrect";
    }

    template 'sign-in', $tokens;
};

1;
