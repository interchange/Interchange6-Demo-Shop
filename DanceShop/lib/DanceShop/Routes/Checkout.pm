package DanceShop::Routes::Checkout;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Interchange6;

any '/checkout' => sub {
    my $out;

    if (config->{checkout_type} eq 'multi') {
        $out = template 'checkout-multipage', {cart => shop_cart};
    }
    else {
        $out = template 'checkout', {cart => shop_cart};
    }

    return $out;
};

1;
