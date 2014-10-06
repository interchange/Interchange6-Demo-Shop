package DanceShop::Routes::Checkout;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Interchange6;

any '/checkout' => sub {
    template 'checkout', {cart => shop_cart};
};

1;
