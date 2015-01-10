package DanceShop::Routes::Checkout;

use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Interchange6;

# our logic - we got x checkout steps
# last step is saved in session
#
# current step exists ?
# if yes, check if we need to validate input
# if successful, go to next step
# if failure, stay on current step

any '/checkout' => sub {
    my $out;

    # Steps
    # 1 - Address
    # 2 - Shipping
    # 3 - Gift
    # 4 - Payment
    # 5 - Receipt

    my @steps = ({
                     name => 'address',
                     template => 'checkout-multipage-address',
                 },
                 {
                     name => 'shipping',
                     template => 'checkout-multipage-shipping',
                 },
                 {
                     name => 'gift',
                     template => 'checkout-multipage-gift',
                 },
                 {
                     name => 'payment',
                     template => 'checkout-multipage-payment',
                 },
                 {
                     name => 'receipt',
                     template => 'checkout-receipt',
                 }
             );

    if (config->{checkout_type} eq 'multi') {
        my $current_step = session('checkout_step');

        if ($current_step) {
            # validation ?
            $current_step = next_step(\@steps, $current_step);
        }
        else {
            $current_step = $steps[0];
        }

        session checkout_step => $current_step;

        debug "Multi page: ", $current_step;

        $out = template $current_step->{template},
            {cart => shop_cart};
    }
    else {

        debug "Single page for checkout.";

        $out = template 'checkout', {cart => shop_cart};
    }

    return $out;
};

sub next_step {
    my ($steps_ref, $current_step) = @_;
    my $next_step = {};

    for my $step (reverse @$steps_ref) {
        if ($current_step->{name} eq $step->{name}) {
            last;
        }
        $next_step = $step;
    }

    return $next_step;
}

1;
